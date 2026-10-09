using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Security;
using System.Security.Cryptography;
using System.Text;

namespace Levmet.Setup {
    public sealed class EnvironmentSetupException : Exception {
        public EnvironmentSetupException(string message) : base(message) {}
    }
    // Windows PowerShell 5.1/.NET Framework: authenticated encryption without downloads.
    public static class EnvironmentEnvelope {
        private static readonly byte[] Magic = Encoding.ASCII.GetBytes("LVMENV01");
        private const int Iterations = 600000;
        private const int MaximumBytes = 4 * 1024 * 1024;

        private static byte[] PasswordBytes(SecureString password) {
            if (password == null || password.Length < 12 || password.Length > 1024)
                throw new ArgumentException("Use a transfer passphrase between 12 and 1024 characters.");
            IntPtr ptr = Marshal.SecureStringToGlobalAllocUnicode(password);
            char[] chars = new char[password.Length];
            try {
                Marshal.Copy(ptr, chars, 0, chars.Length);
                return Encoding.UTF8.GetBytes(chars);
            } finally {
                Array.Clear(chars, 0, chars.Length);
                Marshal.ZeroFreeGlobalAllocUnicode(ptr);
            }
        }
        private static byte[] Derive(SecureString password, byte[] salt) {
            byte[] bytes = PasswordBytes(password);
            try {
                using (var derive = new Rfc2898DeriveBytes(bytes, salt, Iterations, HashAlgorithmName.SHA256))
                    return derive.GetBytes(64);
            } finally { Array.Clear(bytes, 0, bytes.Length); }
        }
        private static byte[] Slice(byte[] data, int offset, int length) {
            var output = new byte[length];
            Buffer.BlockCopy(data, offset, output, 0, length);
            return output;
        }
        private static bool Equal(byte[] left, byte[] right) {
            if (left.Length != right.Length) return false;
            int difference = 0;
            for (int i = 0; i < left.Length; ++i) difference |= left[i] ^ right[i];
            return difference == 0;
        }
        public static string Protect(byte[] plain, SecureString password) {
            if (plain == null || plain.Length > MaximumBytes) throw new ArgumentException("Transfer payload is too large.");
            var salt = new byte[32];
            var iv = new byte[16];
            using (var random = RandomNumberGenerator.Create()) { random.GetBytes(salt); random.GetBytes(iv); }
            var keys = Derive(password, salt);
            try {
                byte[] cipher;
                using (var aes = Aes.Create()) {
                    aes.Key = Slice(keys, 0, 32); aes.IV = iv;
                    aes.Mode = CipherMode.CBC; aes.Padding = PaddingMode.PKCS7;
                    using (var encryptor = aes.CreateEncryptor()) cipher = encryptor.TransformFinalBlock(plain, 0, plain.Length);
                }
                using (var stream = new MemoryStream()) {
                    stream.Write(Magic, 0, Magic.Length); stream.Write(salt, 0, salt.Length);
                    stream.Write(iv, 0, iv.Length); stream.Write(cipher, 0, cipher.Length);
                    byte[] authenticated = stream.ToArray();
                    using (var hmac = new HMACSHA256(Slice(keys, 32, 32))) {
                        var tag = hmac.ComputeHash(authenticated);
                        stream.Write(tag, 0, tag.Length);
                    }
                    return Convert.ToBase64String(stream.ToArray());
                }
            } finally { Array.Clear(keys, 0, keys.Length); }
        }
        public static byte[] Unprotect(string encoded, SecureString password) {
            if (encoded == null || encoded.Length > MaximumBytes * 2) throw new ArgumentException("Invalid transfer file.");
            byte[] data;
            try { data = Convert.FromBase64String(encoded); }
            catch (FormatException) { throw new ArgumentException("Invalid transfer file."); }
            if (data.Length < 104 || (data.Length - 88) % 16 != 0 || !Equal(Slice(data, 0, 8), Magic))
                throw new ArgumentException("Invalid transfer file or unsupported version.");
            var keys = Derive(password, Slice(data, 8, 32));
            try {
                using (var hmac = new HMACSHA256(Slice(keys, 32, 32))) {
                    var expected = hmac.ComputeHash(data, 0, data.Length - 32);
                    if (!Equal(expected, Slice(data, data.Length - 32, 32)))
                        throw new CryptographicException("Wrong passphrase or damaged transfer file. Nothing was changed.");
                }
                using (var aes = Aes.Create()) {
                    aes.Key = Slice(keys, 0, 32); aes.IV = Slice(data, 40, 16);
                    aes.Mode = CipherMode.CBC; aes.Padding = PaddingMode.PKCS7;
                    using (var decryptor = aes.CreateDecryptor()) return decryptor.TransformFinalBlock(data, 56, data.Length - 88);
                }
            } finally { Array.Clear(keys, 0, keys.Length); }
        }
    }

    public sealed class CredentialRecord {
        public string Target;
        public string UserName;
        public string BlobBase64;
    }
    public static class CredentialStore {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct NativeCredential {
            public uint Flags, Type;
            public string TargetName, Comment;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
            public uint CredentialBlobSize;
            public IntPtr CredentialBlob;
            public uint Persist, AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias, UserName;
        }
        [DllImport("advapi32.dll", EntryPoint="CredReadW", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern bool ReadNative(string target, uint type, uint flags, out IntPtr credential);
        [DllImport("advapi32.dll", EntryPoint="CredWriteW", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern bool WriteNative(ref NativeCredential credential, uint flags);
        [DllImport("advapi32.dll", EntryPoint="CredDeleteW", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern bool DeleteNative(string target, uint type, uint flags);
        [DllImport("advapi32.dll")] private static extern void CredFree(IntPtr credential);

        public static CredentialRecord Read(string target) {
            IntPtr pointer;
            if (!ReadNative(target, 1, 0, out pointer)) {
                int error = Marshal.GetLastWin32Error();
                if (error == 1168) return null;
                throw new Win32Exception(error, "Could not read the requested Windows credential.");
            }
            try {
                var value = (NativeCredential)Marshal.PtrToStructure(pointer, typeof(NativeCredential));
                byte[] blob = new byte[value.CredentialBlobSize];
                try {
                    Marshal.Copy(value.CredentialBlob, blob, 0, blob.Length);
                    return new CredentialRecord {Target=target, UserName=value.UserName, BlobBase64=Convert.ToBase64String(blob)};
                } finally { Array.Clear(blob, 0, blob.Length); }
            } finally { CredFree(pointer); }
        }
        public static void Write(string target, string username, string blobBase64) {
            byte[] blob = Convert.FromBase64String(blobBase64);
            if (blob.Length > 2560) throw new ArgumentException("Windows credential is too large.");
            IntPtr pointer = Marshal.AllocHGlobal(blob.Length);
            try {
                Marshal.Copy(blob, 0, pointer, blob.Length);
                var value = new NativeCredential {Type=1, TargetName=target, UserName=username,
                    CredentialBlob=pointer, CredentialBlobSize=(uint)blob.Length, Persist=2,
                    Comment="Levmet code environment migration"};
                if (!WriteNative(ref value, 0)) throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not write the requested Windows credential.");
            } finally {
                for (int i=0; i<blob.Length; ++i) Marshal.WriteByte(pointer, i, 0);
                Marshal.FreeHGlobal(pointer); Array.Clear(blob, 0, blob.Length);
            }
        }
        public static void Delete(string target) {
            if (!DeleteNative(target, 1, 0) && Marshal.GetLastWin32Error() != 1168)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not restore the requested Windows credential.");
        }
    }
}
