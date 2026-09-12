// AudioLevelHelper - samples the peak level of the default playback and recording
// devices and writes them to a text file for Rainmeter to read.
// Depends only on the built-in Windows Core Audio (WASAPI) COM interfaces; no third-party libraries.
//
// Usage: AudioLevelHelper.exe --out <path> [--interval 80] [--decay 0.80] [--gain-out 1.0] [--gain-mic 1.0]
// Output (UTF-8):
//   out=<0-100>
//   mic=<0-100>
//   name_out=<friendly device name>
//   name_mic=<friendly device name>

using System;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace AudioVolume.LevelHelper
{
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    internal class MMDeviceEnumeratorComObject { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceEnumerator
    {
        int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices);
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
        int GetDevice(string id, out IMMDevice device);
        int RegisterEndpointNotificationCallback(IntPtr client);
        int UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceCollection
    {
        int GetCount(out int count);
        int Item(int index, out IMMDevice device);
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    internal struct PROPERTYKEY
    {
        public Guid fmtid;
        public int pid;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct PROPVARIANT
    {
        public ushort vt;
        public ushort wReserved1;
        public ushort wReserved2;
        public ushort wReserved3;
        public IntPtr p;
        public int p2;
    }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IPropertyStore
    {
        int GetCount(out int count);
        int GetAt(int index, out PROPERTYKEY key);
        int GetValue(ref PROPERTYKEY key, out PROPVARIANT value);
        int SetValue(ref PROPERTYKEY key, ref PROPVARIANT value);
        int Commit();
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDevice
    {
        int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.Interface)] out IAudioMeterInformation iface);
        int OpenPropertyStore(int stgmAccess, out IPropertyStore properties);
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        int GetState(out int state);
    }

    [ComImport, Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioMeterInformation
    {
        int GetPeakValue(out float peak);
        int GetMeteringChannelCount(out int channelCount);
        int GetChannelsPeakValues(int channelCount, [Out] float[] peakValues);
        int QueryHardwareSupport(out int hardwareSupportMask);
    }

    internal static class Program
    {
        private const int eRender = 0;
        private const int eCapture = 1;
        private const int eConsole = 0;
        private const int CLSCTX_ALL = 23;
        private const short VT_LPWSTR = 31;

        private static readonly Guid IID_IAudioMeterInformation = new Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064");
        private static readonly PROPERTYKEY PKEY_Device_FriendlyName =
            new PROPERTYKEY { fmtid = new Guid("A45C254E-DF1C-4EFD-8020-67D146A850E0"), pid = 14 };

        private static string _outPath;
        private static int _interval = 80;
        private static double _decay = 0.80;
        private static double _gainOut = 1.0;
        private static double _gainMic = 1.0;

        private static void Main(string[] args)
        {
            if (!ParseArgs(args))
            {
                Console.Error.WriteLine("usage: AudioLevelHelper --out <txt> [--interval 80] [--decay 0.80] [--gain-out 1.0] [--gain-mic 1.0]");
                Environment.Exit(2);
            }

            bool createdNew;
            Mutex single = new Mutex(true, "Global\\AudioVolumeLevelHelper", out createdNew);
            if (!createdNew) return;

            IMMDeviceEnumerator enumerator = null;
            try
            {
                enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
            }
            catch
            {
                Console.Error.WriteLine("cannot create device enumerator");
                Environment.Exit(3);
            }

            double smOut = 0.0, smMic = 0.0;
            string nameOut = "", nameMic = "";
            int nameTick = 0;

            while (true)
            {
                // ???????? ~40 ??? 3 ????????
                if (nameTick == 0)
                {
                    nameOut = ReadDeviceName(enumerator, eRender);
                    nameMic = ReadDeviceName(enumerator, eCapture);
                }
                nameTick = (nameTick + 1) % 40;

                double rawOut = ReadPeak(enumerator, eRender);
                double rawMic = ReadPeak(enumerator, eCapture);

                smOut = rawOut > smOut ? rawOut : smOut * _decay;
                smMic = rawMic > smMic ? rawMic : smMic * _decay;

                double outPct = Clamp(smOut * 100.0 * _gainOut);
                double micPct = Clamp(smMic * 100.0 * _gainMic);

                try
                {
                    StringBuilder sb = new StringBuilder();
                    sb.Append("out=").Append(((int)Math.Round(outPct)).ToString(CultureInfo.InvariantCulture)).Append("\r\n");
                    sb.Append("mic=").Append(((int)Math.Round(micPct)).ToString(CultureInfo.InvariantCulture)).Append("\r\n");
                    sb.Append("name_out=").Append(nameOut).Append("\r\n");
                    sb.Append("name_mic=").Append(nameMic).Append("\r\n");
                    File.WriteAllText(_outPath, sb.ToString(), new UTF8Encoding(false));
                }
                catch
                {
                    // ????????????????????
                }

                Thread.Sleep(_interval);
            }
        }

        private static double ReadPeak(IMMDeviceEnumerator enumerator, int flow)
        {
            IMMDevice device = null;
            IAudioMeterInformation meter = null;
            try
            {
                if (enumerator.GetDefaultAudioEndpoint(flow, eConsole, out device) != 0 || device == null) return 0.0;
                Guid iid = IID_IAudioMeterInformation;
                if (device.Activate(ref iid, CLSCTX_ALL, IntPtr.Zero, out meter) != 0 || meter == null) return 0.0;
                float peak;
                if (meter.GetPeakValue(out peak) != 0) return 0.0;
                double v = peak;
                if (v < 0.0) v = 0.0;
                if (v > 1.0) v = 1.0;
                return v;
            }
            catch
            {
                return 0.0;
            }
            finally
            {
                if (meter != null) Marshal.ReleaseComObject(meter);
                if (device != null) Marshal.ReleaseComObject(device);
            }
        }

        private static string ReadDeviceName(IMMDeviceEnumerator enumerator, int flow)
        {
            IMMDevice device = null;
            IPropertyStore store = null;
            try
            {
                if (enumerator.GetDefaultAudioEndpoint(flow, eConsole, out device) != 0 || device == null) return "";
                if (device.OpenPropertyStore(0, out store) != 0 || store == null) return "";
                PROPERTYKEY key = PKEY_Device_FriendlyName;
                PROPVARIANT value;
                if (store.GetValue(ref key, out value) != 0) return "";
                if (value.vt != VT_LPWSTR || value.p == IntPtr.Zero) return "";
                return Marshal.PtrToStringUni(value.p) ?? "";
            }
            catch
            {
                return "";
            }
            finally
            {
                if (store != null) Marshal.ReleaseComObject(store);
                if (device != null) Marshal.ReleaseComObject(device);
            }
        }

        private static double Clamp(double v)
        {
            if (v < 0.0) return 0.0;
            if (v > 100.0) return 100.0;
            return v;
        }

        private static bool ParseArgs(string[] args)
        {
            for (int i = 0; i < args.Length; i++)
            {
                string a = args[i].ToLowerInvariant();
                string next = (i + 1 < args.Length) ? args[i + 1] : null;
                switch (a)
                {
                    case "--out": if (next == null) return false; _outPath = next; i++; break;
                    case "--interval": if (next == null) return false; _interval = int.Parse(next, CultureInfo.InvariantCulture); i++; break;
                    case "--decay": if (next == null) return false; _decay = double.Parse(next, CultureInfo.InvariantCulture); i++; break;
                    case "--gain-out": if (next == null) return false; _gainOut = double.Parse(next, CultureInfo.InvariantCulture); i++; break;
                    case "--gain-mic": if (next == null) return false; _gainMic = double.Parse(next, CultureInfo.InvariantCulture); i++; break;
                    default: return false;
                }
            }
            if (string.IsNullOrEmpty(_outPath)) return false;
            if (_interval < 20) _interval = 20;
            if (_decay < 0.0) _decay = 0.0;
            if (_decay > 0.999) _decay = 0.999;
            return true;
        }
    }
}
