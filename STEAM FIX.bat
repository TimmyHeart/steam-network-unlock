<# : batch portion
@echo off
:: ============================================================
::  Sua loi Steam v5: loi -105, store/community mat giao dien (CSS),
::  avatar bi mac dinh trong game (CS2...). Co RELAY cuc bo vuot chan SNI.
::  Cach dung: double-click file nay, bam Yes khi Windows hoi quyen Admin
::  MADE BY V - TRAN HIEU NGHIA
:: ============================================================
set "SELF=%~f0"
title Sua loi Steam v5
chcp 437 >nul 2>&1

fltmc >nul 2>&1 || (
  if /i "%~1"=="--elevated" (
    echo [!] Khong lay duoc quyen Administrator.
    pause
    exit /b 1
  )
  echo Dang yeu cau quyen Administrator, hay bam Yes...
  powershell -NoProfile -Command "try { Start-Process -FilePath $env:SELF -ArgumentList '--elevated' -Verb RunAs -ErrorAction Stop } catch { Write-Host '[!] Ban da tu choi quyen Administrator.'; Read-Host 'Nhan Enter de thoat' }"
  exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ([IO.File]::ReadAllText($env:SELF))"
exit /b
#>

# ============================================================
#  Phan PowerShell (duoc phan .bat o tren goi lai)
#  NGUYEN TAC: quet truoc, chi dung vao cai dang loi, luon co ban sao luu hosts.
#  v5: them RELAY cuc bo - chia nho TLS ClientHello de vuot bo loc SNI cua nha mang.
# ============================================================

Add-Type -AssemblyName System.Net.Http
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Ver       = 'v5'
$DataDir   = Join-Path $env:ProgramData 'SteamFix'
$RelayPs1  = Join-Path $DataDir 'relay.ps1'
$TaskName  = 'SteamFix Relay'
$RelayPort = 443
$ProbePort = 18443

# --- Ten mien Steam di qua relay (loc HTTPS that). Ten khong ton tai se tu bi bo qua. ---
$RelayHosts = New-Object System.Collections.Generic.List[string]
foreach ($h in @(
    'store.steampowered.com', 'steamcommunity.com', 'api.steampowered.com', 'login.steampowered.com',
    'help.steampowered.com', 'checkout.steampowered.com', 'media.steampowered.com',
    'steamcdn-a.akamaihd.net', 'steamuserimages-a.akamaihd.net', 'steamcommunity-a.akamaihd.net',
    'cdn.steamstatic.com', 'avatars.steamstatic.com', 'client-update.steamstatic.com',
    'clientconfig.akamai.steamstatic.com', 'clientconfig.fastly.steamstatic.com')) { $RelayHosts.Add($h) }
foreach ($f in @('store', 'shared', 'community', 'cdn', 'clan', 'avatars')) {
    foreach ($c in @('fastly', 'akamai', 'cloudflare')) { $RelayHosts.Add("$f.$c.steamstatic.com") }
}
# Domain nay la may chu Steam (khong phai web) -> chi kiem tra DNS
$DnsOnlyHosts = @('cmp1-sgp1.steamserver.net')
$SteamHosts   = @($RelayHosts) + @($DnsOnlyHosts)

$DnsPreset = @{
    Name = 'Google + Cloudflare (du phong cheo)'
    V4   = @('8.8.8.8', '1.1.1.1', '8.8.4.4', '1.0.0.1')
    V6   = @('2001:4860:4860::8888', '2606:4700:4700::1111', '2001:4860:4860::8844', '2606:4700:4700::1001')
}

$DohTemplates = [ordered]@{
    '8.8.8.8'              = 'https://dns.google/dns-query'
    '8.8.4.4'              = 'https://dns.google/dns-query'
    '1.1.1.1'              = 'https://cloudflare-dns.com/dns-query'
    '1.0.0.1'              = 'https://cloudflare-dns.com/dns-query'
    '2001:4860:4860::8888' = 'https://dns.google/dns-query'
    '2001:4860:4860::8844' = 'https://dns.google/dns-query'
    '2606:4700:4700::1111' = 'https://cloudflare-dns.com/dns-query'
    '2606:4700:4700::1001' = 'https://cloudflare-dns.com/dns-query'
}

# Chi coi la "dong chan Steam" khi: dang hoat dong + tro ve 127.x / 0.0.0.0 / ::1 + ten mien thuoc Steam
$SteamDomainRegex = '(^|\.)(steampowered\.com|steamcommunity\.com|steamstatic\.com|steamserver\.net|steamcontent\.com|steamgames\.com|steamusercontent\.com|valvesoftware\.com)$|^steam[a-z0-9-]*\.akamaihd\.net$'

$HostsPath  = "$env:SystemRoot\System32\drivers\etc\hosts"
$HostsBegin = '# >>> SteamFix BEGIN (tu dong tao - dung muc [4] trong tool de go) >>>'
$HostsEnd   = '# <<< SteamFix END <<<'
$QuicRule   = 'SteamFix - Chan QUIC (steamwebhelper)'

$global:SteamScanDone    = $false
$global:SteamFailedHosts = @()

# ------------------------------------------------------------
#  Ma nguon RELAY (C#, bien dich tai cho bang Add-Type - khong can cai them gi)
#  Steam -> 127.0.0.1:443 -> [chia nho ClientHello] -> CDN that. Chi chuyen byte TLS, khong giai ma.
# ------------------------------------------------------------
$RelayCs = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

namespace SteamFix
{
    public class SniInfo
    {
        public string Host;
        public int Offset;
        public int Length;
    }

    public class ProbeResult
    {
        public string Host;
        public bool Ok;
        public string Info;
        public string Mode;
        public string Ip;
    }

    // Relay TCP cuc bo: Steam -> 127.0.0.1:443 -> (chia nho ClientHello) -> CDN that.
    // Chi chuyen tiep byte TLS nguyen ven, KHONG giai ma, KHONG dung chung chi.
    public static class Relay
    {
        public static readonly string[] ModeNames = new string[] { "tcp-early", "rec-sni", "tcp-sni", "plain" };
        const int ModePlain = 3;

        public static string DataDir = "";
        public static int UpstreamPort = 443;
        public static int HttpPort = 80;
        public static int UpstreamHttpPort = 80;
        public static int SplitDelayMs = 2;
        public static int ForceMode = -1;
        public static int ConnectTimeoutMs = 3000;
        public static int FirstByteTimeoutMs = 4000;
        public static bool NoNetworkDns = false;
        public static bool AcceptAnyCert = false;

        static readonly Regex AllowRx = new Regex(
            @"(^|\.)(steampowered\.com|steamcommunity\.com|steamstatic\.com|steamcontent\.com|steamgames\.com|steamusercontent\.com|steam-chat\.com|valvesoftware\.com)$|^steam[a-z0-9-]*\.akamaihd\.net$|^steampipe[a-z0-9.-]*\.akamaized\.net$",
            RegexOptions.IgnoreCase);

        class DnsEntry { public List<IPAddress> Ips; public DateTime At; }
        class HostStat { public int Ok; public int Fail; public string Mode = ""; public bool Dirty; }

        static readonly object Sync = new object();
        static readonly object LogSync = new object();
        static readonly Random Rng = new Random();
        static Socket listener;
        static Socket listener80;
        static volatile bool running;
        static int[] modeScore = new int[4];
        static Dictionary<string, string> lastGood = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        static Dictionary<string, DnsEntry> dnsCache = new Dictionary<string, DnsEntry>(StringComparer.OrdinalIgnoreCase);
        static Dictionary<string, HostStat> stats = new Dictionary<string, HostStat>(StringComparer.OrdinalIgnoreCase);
        static Dictionary<string, string> modeUsed = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        static Dictionary<string, string> ipUsed = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        static Dictionary<string, string> failInfo = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        static bool lastGoodDirty;
        static Dictionary<string, bool> httpPlainBad = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);

        // ------------------------------------------------------------ log
        public static void Log(string msg)
        {
            if (string.IsNullOrEmpty(DataDir)) return;
            try
            {
                lock (LogSync)
                {
                    string p = Path.Combine(DataDir, "relay.log");
                    FileInfo fi = new FileInfo(p);
                    if (fi.Exists && fi.Length > 524288)
                    {
                        string old = p + ".old";
                        if (File.Exists(old)) File.Delete(old);
                        File.Move(p, old);
                    }
                    File.AppendAllText(p, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " " + msg + "\r\n");
                }
            }
            catch (Exception) { }
        }

        // ------------------------------------------------------------ start / stop
        public static void Start(string bindIp, int port, string dataDir)
        {
            if (running) return;
            DataDir = dataDir;
            try { Directory.CreateDirectory(dataDir); } catch (Exception) { }
            try
            {
                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
                ServicePointManager.Expect100Continue = false;
                ServicePointManager.DefaultConnectionLimit = 64;
            }
            catch (Exception) { }
            LoadLastGood();
            Socket l = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
            try
            {
                l.Bind(new IPEndPoint(IPAddress.Parse(bindIp), port));
                l.Listen(256);
            }
            catch (Exception)
            {
                l.Close();
                throw;
            }
            listener = l;
            running = true;
            Thread t = new Thread(AcceptLoop);
            t.IsBackground = true;
            t.Start();
            Thread m = new Thread(MaintLoop);
            m.IsBackground = true;
            m.Start();
            Log("start " + bindIp + ":" + port + " upstream-port=" + UpstreamPort);
            if (HttpPort > 0)
            {
                try
                {
                    Socket l2 = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
                    try
                    {
                        l2.Bind(new IPEndPoint(IPAddress.Parse(bindIp), HttpPort));
                        l2.Listen(128);
                    }
                    catch (Exception) { l2.Close(); throw; }
                    listener80 = l2;
                    Thread t2 = new Thread(AcceptLoop80);
                    t2.IsBackground = true;
                    t2.Start();
                    Log("http relay " + bindIp + ":" + HttpPort);
                }
                catch (Exception ex)
                {
                    Log("khong mo duoc cong HTTP " + HttpPort + ": " + ex.Message);
                }
            }
        }

        public static void Stop()
        {
            running = false;
            try { if (listener != null) listener.Close(); } catch (Exception) { }
            listener = null;
            try { if (listener80 != null) listener80.Close(); } catch (Exception) { }
            listener80 = null;
            SaveLastGood();
        }

        public static void Run(string bindIp, int port, string dataDir)
        {
            Start(bindIp, port, dataDir);
            while (running) Thread.Sleep(1000);
        }

        static void AcceptLoop()
        {
            while (running)
            {
                Socket c = null;
                try { c = listener.Accept(); }
                catch (Exception)
                {
                    if (!running) break;
                    Thread.Sleep(50);
                    continue;
                }
                Socket cc = c;
                Thread t = new Thread(delegate() { Handle(cc); });
                t.IsBackground = true;
                t.Start();
            }
        }


        // ------------------------------------------------------------ HTTP thuong (cong 80): hosts tro ve 127.0.0.1 thi cong 80 cung phai co nguoi nghe
        static void AcceptLoop80()
        {
            while (running)
            {
                Socket c = null;
                try { c = listener80.Accept(); }
                catch (Exception)
                {
                    if (!running) break;
                    Thread.Sleep(50);
                    continue;
                }
                Socket cc = c;
                Thread t = new Thread(delegate() { Handle80(cc); });
                t.IsBackground = true;
                t.Start();
            }
        }

        static int IndexOfHeaderEnd(byte[] b, int n)
        {
            for (int i = 0; i + 3 < n; i++)
                if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) return i;
            return -1;
        }

        static Socket Attempt80(IPAddress ip, byte[] req, int len, int hostOff, int hostLen, bool split, out byte[] first, out int firstLen)
        {
            first = null;
            firstLen = 0;
            Socket up = null;
            try
            {
                up = new Socket(ip.AddressFamily, SocketType.Stream, ProtocolType.Tcp);
                up.NoDelay = true;
                IAsyncResult ar = up.BeginConnect(ip, UpstreamHttpPort, null, null);
                if (!ar.AsyncWaitHandle.WaitOne(ConnectTimeoutMs)) { up.Close(); return null; }
                up.EndConnect(ar);
                if (split)
                {
                    byte[] copy = new byte[len];
                    Array.Copy(req, copy, len);
                    SendSegments(up, copy, new int[] { hostOff + Math.Max(1, hostLen / 2) });
                }
                else up.Send(req, 0, len, SocketFlags.None);
                up.ReceiveTimeout = 8000;
                byte[] buf = new byte[16384];
                int n = up.Receive(buf);
                if (n < 5 || buf[0] != (byte)'H' || buf[1] != (byte)'T' || buf[2] != (byte)'T' || buf[3] != (byte)'P') { up.Close(); return null; }
                up.ReceiveTimeout = 0;
                up.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.KeepAlive, true);
                first = buf;
                firstLen = n;
                return up;
            }
            catch (Exception)
            {
                try { if (up != null) up.Close(); } catch (Exception) { }
                return null;
            }
        }


        // Stream boc NetworkStream: lan Write dau tien (ClientHello cua SslStream) duoc tach 2 byte dau.
        class FragStream : Stream
        {
            readonly Stream inner;
            bool first = true;
            public FragStream(Stream s) { inner = s; }
            public override bool CanRead { get { return inner.CanRead; } }
            public override bool CanSeek { get { return false; } }
            public override bool CanWrite { get { return inner.CanWrite; } }
            public override void Flush() { inner.Flush(); }
            public override long Length { get { throw new NotSupportedException(); } }
            public override long Position { get { throw new NotSupportedException(); } set { throw new NotSupportedException(); } }
            public override int Read(byte[] buffer, int offset, int count) { return inner.Read(buffer, offset, count); }
            public override long Seek(long offset, SeekOrigin origin) { throw new NotSupportedException(); }
            public override void SetLength(long value) { throw new NotSupportedException(); }
            public override void Write(byte[] buffer, int offset, int count)
            {
                if (first && count > 2)
                {
                    first = false;
                    inner.Write(buffer, offset, 2);
                    inner.Flush();
                    if (SplitDelayMs > 0) Thread.Sleep(SplitDelayMs);
                    inner.Write(buffer, offset + 2, count - 2);
                    return;
                }
                first = false;
                inner.Write(buffer, offset, count);
            }
        }

        // Doi "Connection:" thanh close de upstream dong ket noi sau khi tra loi (don gian hoa framing)
        static byte[] RewriteRequest(byte[] req, int len)
        {
            int end = IndexOfHeaderEnd(req, len);
            string head = Encoding.ASCII.GetString(req, 0, end);
            string[] lines = head.Split(new string[] { "\r\n" }, StringSplitOptions.None);
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < lines.Length; i++)
            {
                string l = lines[i];
                string lo = l.ToLowerInvariant();
                if (i > 0 && (lo.StartsWith("connection:") || lo.StartsWith("proxy-connection:"))) continue;
                sb.Append(l).Append("\r\n");
            }
            sb.Append("Connection: close\r\n\r\n");
            byte[] h = Encoding.ASCII.GetBytes(sb.ToString());
            int bodyStart = end + 4;
            int bodyLen = Math.Max(0, len - bodyStart);
            byte[] o = new byte[h.Length + bodyLen];
            Array.Copy(h, o, h.Length);
            if (bodyLen > 0) Array.Copy(req, bodyStart, o, h.Length, bodyLen);
            return o;
        }

        // Nhan HTTP thuong tu client, noi chuyen voi upstream bang HTTPS (TLS chia nho ClientHello), tra ket qua ve client.
        static bool ServeViaTls(Socket client, string host, List<IPAddress> ips, byte[] req, int reqLen)
        {
            byte[] r2 = RewriteRequest(req, reqLen);
            for (int pass = 0; pass < 2; pass++)
            {
                for (int ii = 0; ii < ips.Count && ii < 2; ii++)
                {
                    Socket up = null;
                    bool delivered = false;
                    try
                    {
                        up = new Socket(ips[ii].AddressFamily, SocketType.Stream, ProtocolType.Tcp);
                        up.NoDelay = true;
                        IAsyncResult ar = up.BeginConnect(ips[ii], UpstreamPort, null, null);
                        if (!ar.AsyncWaitHandle.WaitOne(ConnectTimeoutMs)) { up.Close(); continue; }
                        up.EndConnect(ar);
                        up.ReceiveTimeout = 8000;
                        up.SendTimeout = 8000;
                        NetworkStream ns = new NetworkStream(up, false);
                        Stream baseStream = pass == 0 ? (Stream)new FragStream(ns) : (Stream)ns;
                        System.Net.Security.SslStream ssl = new System.Net.Security.SslStream(baseStream, false,
                            delegate(object snd, X509Certificate cert, System.Security.Cryptography.X509Certificates.X509Chain chain, System.Net.Security.SslPolicyErrors err)
                            { return AcceptAnyCert || err == System.Net.Security.SslPolicyErrors.None; });
                        ssl.AuthenticateAsClient(host, null, System.Security.Authentication.SslProtocols.Tls12, false);
                        ssl.Write(r2, 0, r2.Length);
                        ssl.Flush();
                        byte[] buf = new byte[16384];
                        int n = ssl.Read(buf, 0, buf.Length);
                        if (n < 5 || buf[0] != (byte)'H' || buf[1] != (byte)'T' || buf[2] != (byte)'T' || buf[3] != (byte)'P') { up.Close(); continue; }
                        client.Send(buf, 0, n, SocketFlags.None);
                        delivered = true;
                        while ((n = ssl.Read(buf, 0, buf.Length)) > 0) client.Send(buf, 0, n, SocketFlags.None);
                        try { up.Close(); } catch (Exception) { }
                        lock (Sync) { ipUsed[host] = ips[ii].ToString(); modeUsed[host] = "http-tls"; }
                        return true;
                    }
                    catch (Exception)
                    {
                        try { if (up != null) up.Close(); } catch (Exception) { }
                        if (delivered)
                        {
                            lock (Sync) { ipUsed[host] = ips[ii].ToString(); modeUsed[host] = "http-tls"; }
                            return true;
                        }
                    }
                }
            }
            return false;
        }

        static void Handle80(Socket client)
        {
            Socket up = null;
            try
            {
                client.NoDelay = true;
                client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.KeepAlive, true);
                client.ReceiveTimeout = 8000;
                byte[] buf = new byte[17000];
                int have = 0;
                while (IndexOfHeaderEnd(buf, have) < 0)
                {
                    if (have >= buf.Length) { client.Close(); return; }
                    int n = client.Receive(buf, have, buf.Length - have, SocketFlags.None);
                    if (n <= 0) { client.Close(); return; }
                    have += n;
                }
                client.ReceiveTimeout = 0;
                string head = Encoding.ASCII.GetString(buf, 0, have);
                Match m = Regex.Match(head, @"(?im)^Host:[ \t]*([^\r\n:]+)");
                if (!m.Success) { Log("http reject (khong co Host)"); client.Close(); return; }
                string host = m.Groups[1].Value.Trim().ToLowerInvariant();
                if (!AllowRx.IsMatch(host)) { Log("http reject host=" + host); client.Close(); return; }
                int hostOff = m.Groups[1].Index;
                int hostLen = m.Groups[1].Length;
                List<IPAddress> ips = Resolve(host);
                byte[] first = null;
                int firstLen = 0;
                string modeName = "http-plain";
                bool plainBad;
                lock (Sync) { plainBad = httpPlainBad.ContainsKey(host); }
                if (!plainBad)
                {
                    for (int pass = 0; pass < 2 && up == null; pass++)
                    {
                        for (int ii = 0; ii < ips.Count && ii < 2 && up == null; ii++)
                        {
                            up = Attempt80(ips[ii], buf, have, hostOff, hostLen, pass == 1, out first, out firstLen);
                            if (up != null)
                            {
                                modeName = pass == 1 ? "http-split" : "http-plain";
                                lock (Sync) { ipUsed[host] = ips[ii].ToString(); modeUsed[host] = modeName; }
                            }
                        }
                    }
                    if (up == null) { lock (Sync) { httpPlainBad[host] = true; } Log("http plain that bai -> chuyen sang HTTPS cho " + host); }
                }
                if (up == null)
                {
                    if (ServeViaTls(client, host, ips, buf, have))
                    {
                        Stat(host, true, "http-tls");
                        try { client.Close(); } catch (Exception) { }
                        return;
                    }
                    Stat(host, false, null);
                    Log("http fail " + host + " ips=" + JoinIps(ips));
                    client.Close();
                    return;
                }
                Stat(host, true, modeName);
                client.Send(first, 0, firstLen, SocketFlags.None);
                Socket u2 = up;
                Socket c2 = client;
                Thread t = new Thread(delegate() { Pump(u2, c2); });
                t.IsBackground = true;
                t.Start();
                Pump(client, up);
            }
            catch (Exception)
            {
                try { client.Close(); } catch (Exception) { }
                try { if (up != null) up.Close(); } catch (Exception) { }
            }
        }

        // ------------------------------------------------------------ xu ly 1 ket noi
        static void Handle(Socket client)
        {
            Socket up = null;
            try
            {
                client.NoDelay = true;
                client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.KeepAlive, true);
                byte[] hello = ReadHello(client);
                if (hello == null) { client.Close(); return; }
                SniInfo sni = ParseSni(hello);
                if (sni == null || !AllowRx.IsMatch(sni.Host))
                {
                    Log("reject sni=" + (sni == null ? "-" : sni.Host));
                    client.Close();
                    return;
                }
                byte[] first;
                int firstLen;
                int modeIdx;
                up = ConnectUpstream(sni, hello, out first, out firstLen, out modeIdx);
                if (up == null)
                {
                    Stat(sni.Host, false, null);
                    client.Close();
                    return;
                }
                Stat(sni.Host, true, ModeNames[modeIdx]);
                client.Send(first, 0, firstLen, SocketFlags.None);
                Socket u2 = up;
                Socket c2 = client;
                Thread t = new Thread(delegate() { Pump(u2, c2); });
                t.IsBackground = true;
                t.Start();
                Pump(client, up);
            }
            catch (Exception)
            {
                try { client.Close(); } catch (Exception) { }
                try { if (up != null) up.Close(); } catch (Exception) { }
            }
        }

        static void Pump(Socket src, Socket dst)
        {
            byte[] buf = new byte[65536];
            try
            {
                while (true)
                {
                    int n = src.Receive(buf);
                    if (n <= 0) break;
                    dst.Send(buf, 0, n, SocketFlags.None);
                }
            }
            catch (Exception) { }
            try { src.Shutdown(SocketShutdown.Both); } catch (Exception) { }
            try { dst.Shutdown(SocketShutdown.Both); } catch (Exception) { }
            try { src.Close(); } catch (Exception) { }
            try { dst.Close(); } catch (Exception) { }
        }

        // ------------------------------------------------------------ doc + phan tich ClientHello
        static byte[] ReadHello(Socket s)
        {
            s.ReceiveTimeout = 8000;
            byte[] buf = new byte[17000];
            int have = 0;
            int need = 0;
            while (true)
            {
                if (need == 0 && have >= 5)
                {
                    if (buf[0] != 0x16 || buf[1] != 3) return null;
                    int len = (buf[3] << 8) | buf[4];
                    if (len < 4 || len > 16384) return null;
                    need = 5 + len;
                }
                if (need > 0 && have >= need) break;
                int n = s.Receive(buf, have, buf.Length - have, SocketFlags.None);
                if (n <= 0) return null;
                have += n;
            }
            s.ReceiveTimeout = 0;
            byte[] hello = new byte[need];
            Array.Copy(buf, hello, need);
            return hello;
        }

        public static SniInfo ParseSni(byte[] h)
        {
            try
            {
                int p = 5;
                if (h.Length < 50 || h[p] != 1) return null;
                p += 4;
                p += 2 + 32;
                p += 1 + h[p];
                p += 2 + ((h[p] << 8) | h[p + 1]);
                p += 1 + h[p];
                int extTotal = (h[p] << 8) | h[p + 1];
                p += 2;
                int end = Math.Min(p + extTotal, h.Length);
                while (p + 4 <= end)
                {
                    int type = (h[p] << 8) | h[p + 1];
                    int elen = (h[p + 2] << 8) | h[p + 3];
                    p += 4;
                    if (type == 0)
                    {
                        int q = p + 2;
                        if (q + 3 <= end && h[q] == 0)
                        {
                            int nl = (h[q + 1] << 8) | h[q + 2];
                            if (nl > 0 && q + 3 + nl <= h.Length)
                            {
                                SniInfo si = new SniInfo();
                                si.Host = Encoding.ASCII.GetString(h, q + 3, nl).ToLowerInvariant();
                                si.Offset = q + 3;
                                si.Length = nl;
                                return si;
                            }
                        }
                        return null;
                    }
                    p += elen;
                }
            }
            catch (Exception) { }
            return null;
        }

        // ------------------------------------------------------------ gui ClientHello theo tung kieu
        static void SendSegments(Socket s, byte[] data, int[] cuts)
        {
            int prev = 0;
            for (int i = 0; i < cuts.Length; i++)
            {
                int c = cuts[i];
                if (c <= prev || c >= data.Length) continue;
                s.Send(data, prev, c - prev, SocketFlags.None);
                prev = c;
                if (SplitDelayMs > 0) Thread.Sleep(SplitDelayMs);
            }
            s.Send(data, prev, data.Length - prev, SocketFlags.None);
        }

        // Tach 1 record TLS thanh 2 record (handshake bi chia doi tai vi tri cut)
        static byte[] SplitRecords(byte[] hello, int cut)
        {
            int payload = hello.Length - 5;
            int k = cut - 5;
            if (k < 1 || k >= payload) return hello;
            byte[] o = new byte[hello.Length + 5];
            o[0] = hello[0]; o[1] = hello[1]; o[2] = hello[2];
            o[3] = (byte)(k >> 8); o[4] = (byte)(k & 0xFF);
            Array.Copy(hello, 5, o, 5, k);
            int p2 = 5 + k;
            int rest = payload - k;
            o[p2] = hello[0]; o[p2 + 1] = hello[1]; o[p2 + 2] = hello[2];
            o[p2 + 3] = (byte)(rest >> 8); o[p2 + 4] = (byte)(rest & 0xFF);
            Array.Copy(hello, 5 + k, o, p2 + 5, rest);
            return o;
        }

        static void SendHello(Socket up, byte[] hello, SniInfo sni, int mode)
        {
            int cut = sni.Offset + Math.Max(1, sni.Length / 2);
            switch (mode)
            {
                case 0:
                    SendSegments(up, hello, new int[] { 2 });
                    break;
                case 1:
                    {
                        byte[] f = SplitRecords(hello, cut);
                        SendSegments(up, f, new int[] { cut });
                        break;
                    }
                case 2:
                    SendSegments(up, hello, new int[] { cut });
                    break;
                default:
                    up.Send(hello, 0, hello.Length, SocketFlags.None);
                    break;
            }
        }

        // ------------------------------------------------------------ ket noi upstream (thu nhieu kieu / nhieu IP)
        static int[] ModeOrder()
        {
            if (ForceMode >= 0 && ForceMode < 4) return new int[] { ForceMode };
            int[] idx = new int[] { 0, 1, 2, 3 };
            lock (Sync)
            {
                for (int i = 1; i < 4; i++)
                {
                    int key = idx[i];
                    int j = i - 1;
                    while (j >= 0 && modeScore[idx[j]] < modeScore[key]) { idx[j + 1] = idx[j]; j--; }
                    idx[j + 1] = key;
                }
            }
            return idx;
        }

        static Socket Attempt(IPAddress ip, byte[] hello, SniInfo sni, int mode, out byte[] first, out int firstLen)
        {
            first = null;
            firstLen = 0;
            Socket up = null;
            try
            {
                up = new Socket(ip.AddressFamily, SocketType.Stream, ProtocolType.Tcp);
                up.NoDelay = true;
                IAsyncResult ar = up.BeginConnect(ip, UpstreamPort, null, null);
                if (!ar.AsyncWaitHandle.WaitOne(ConnectTimeoutMs)) { up.Close(); return null; }
                up.EndConnect(ar);
                SendHello(up, hello, sni, mode);
                up.ReceiveTimeout = FirstByteTimeoutMs;
                byte[] buf = new byte[16384];
                int n = up.Receive(buf);
                if (n <= 0) { up.Close(); return null; }
                bool good = buf[0] == 0x16 || (mode == ModePlain && buf[0] == 0x15);
                if (!good) { up.Close(); return null; }
                up.ReceiveTimeout = 0;
                up.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.KeepAlive, true);
                first = buf;
                firstLen = n;
                return up;
            }
            catch (Exception)
            {
                try { if (up != null) up.Close(); } catch (Exception) { }
                return null;
            }
        }

        static Socket ConnectUpstream(SniInfo sni, byte[] hello, out byte[] first, out int firstLen, out int modeOut)
        {
            first = null;
            firstLen = 0;
            modeOut = -1;
            List<IPAddress> ips = Resolve(sni.Host);
            if (ips.Count == 0)
            {
                lock (Sync) { failInfo[sni.Host] = "khong phan giai duoc IP"; }
                Log("no-ip " + sni.Host);
                return null;
            }
            int[] order = ModeOrder();
            Stopwatch sw = Stopwatch.StartNew();
            int attempts = 0;
            for (int mi = 0; mi < order.Length; mi++)
            {
                for (int ii = 0; ii < ips.Count && ii < 2; ii++)
                {
                    if (sw.Elapsed.TotalSeconds > 14) goto Failed;
                    attempts++;
                    Socket s = Attempt(ips[ii], hello, sni, order[mi], out first, out firstLen);
                    if (s != null)
                    {
                        modeOut = order[mi];
                        string ipStr = ips[ii].ToString();
                        lock (Sync)
                        {
                            modeScore[modeOut]++;
                            modeUsed[sni.Host] = ModeNames[modeOut];
                            ipUsed[sni.Host] = ipStr;
                            failInfo.Remove(sni.Host);
                            string old;
                            if (!lastGood.TryGetValue(sni.Host, out old) || old != ipStr)
                            {
                                lastGood[sni.Host] = ipStr;
                                lastGoodDirty = true;
                            }
                        }
                        return s;
                    }
                }
            }
        Failed:
            lock (Sync) { failInfo[sni.Host] = "moi kieu chia nho + IP deu bi RESET/timeout (" + attempts + " lan thu)"; }
            Log("fail " + sni.Host + " ips=" + JoinIps(ips) + " attempts=" + attempts);
            return null;
        }

        static string JoinIps(List<IPAddress> ips)
        {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < ips.Count && i < 4; i++)
            {
                if (i > 0) sb.Append(',');
                sb.Append(ips[i].ToString());
            }
            return sb.ToString();
        }

        // ------------------------------------------------------------ thong ke
        static void Stat(string host, bool ok, string mode)
        {
            lock (Sync)
            {
                HostStat st;
                if (!stats.TryGetValue(host, out st)) { st = new HostStat(); stats[host] = st; }
                if (ok) { st.Ok++; if (mode != null) st.Mode = mode; } else st.Fail++;
                st.Dirty = true;
            }
        }

        public static string ModeOf(string host)
        {
            lock (Sync) { string m; return modeUsed.TryGetValue(host, out m) ? m : ""; }
        }

        public static string IpOf(string host)
        {
            lock (Sync) { string m; return ipUsed.TryGetValue(host, out m) ? m : ""; }
        }

        public static string FailOf(string host)
        {
            lock (Sync) { string m; return failInfo.TryGetValue(host, out m) ? m : ""; }
        }

        // ------------------------------------------------------------ DNS (DoH + UDP, song song)
        static void AddIp(List<IPAddress> l, IPAddress ip)
        {
            if (ip == null || ip.AddressFamily != AddressFamily.InterNetwork) return;
            byte[] b = ip.GetAddressBytes();
            if ((b[0] == 0 || b[0] == 127) && !NoNetworkDns) return;
            for (int i = 0; i < l.Count; i++) if (l[i].Equals(ip)) return;
            l.Add(ip);
        }

        static List<IPAddress> DohQuery(string url, bool cf)
        {
            List<IPAddress> r = new List<IPAddress>();
            try
            {
                HttpWebRequest rq = (HttpWebRequest)WebRequest.Create(url);
                rq.Proxy = null;
                rq.Timeout = 4000;
                rq.ReadWriteTimeout = 4000;
                rq.UserAgent = "SteamFix/5";
                if (cf) rq.Accept = "application/dns-json";
                using (WebResponse resp = rq.GetResponse())
                using (StreamReader sr = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
                {
                    string body = sr.ReadToEnd();
                    foreach (Match m in Regex.Matches(body, @"\{[^{}]*\}"))
                    {
                        string o = m.Value;
                        if (!Regex.IsMatch(o, "\"type\"\\s*:\\s*1\\s*[,}]")) continue;
                        Match d = Regex.Match(o, "\"data\"\\s*:\\s*\"(\\d+\\.\\d+\\.\\d+\\.\\d+)\"");
                        IPAddress ip;
                        if (d.Success && IPAddress.TryParse(d.Groups[1].Value, out ip)) AddIp(r, ip);
                    }
                }
            }
            catch (Exception) { }
            return r;
        }

        static byte[] BuildQuery(string host, byte id0, byte id1)
        {
            List<byte> b = new List<byte>();
            b.Add(id0); b.Add(id1);
            b.Add(0x01); b.Add(0x00);
            b.Add(0); b.Add(1);
            b.Add(0); b.Add(0); b.Add(0); b.Add(0); b.Add(0); b.Add(0);
            string[] labels = host.Split('.');
            for (int i = 0; i < labels.Length; i++)
            {
                byte[] lb = Encoding.ASCII.GetBytes(labels[i]);
                b.Add((byte)lb.Length);
                b.AddRange(lb);
            }
            b.Add(0);
            b.Add(0); b.Add(1);
            b.Add(0); b.Add(1);
            return b.ToArray();
        }

        static int SkipName(byte[] buf, int p, int n)
        {
            while (p < n)
            {
                int b = buf[p];
                if (b == 0) return p + 1;
                if ((b & 0xC0) == 0xC0) return p + 2;
                p += b + 1;
            }
            return n;
        }

        static List<IPAddress> UdpDns(string server, string host)
        {
            List<IPAddress> r = new List<IPAddress>();
            Socket s = null;
            try
            {
                byte id0, id1;
                lock (Sync) { id0 = (byte)Rng.Next(256); id1 = (byte)Rng.Next(256); }
                byte[] q = BuildQuery(host, id0, id1);
                s = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
                s.ReceiveTimeout = 2500;
                s.SendTimeout = 2500;
                s.SendTo(q, new IPEndPoint(IPAddress.Parse(server), 53));
                byte[] buf = new byte[1500];
                EndPoint ep = new IPEndPoint(IPAddress.Any, 0);
                int n = s.ReceiveFrom(buf, ref ep);
                if (n < 12 || buf[0] != id0 || buf[1] != id1 || (buf[3] & 0x0F) != 0) return r;
                int qd = (buf[4] << 8) | buf[5];
                int an = (buf[6] << 8) | buf[7];
                int p = 12;
                for (int i = 0; i < qd; i++) { p = SkipName(buf, p, n); p += 4; }
                for (int i = 0; i < an; i++)
                {
                    p = SkipName(buf, p, n);
                    if (p + 10 > n) break;
                    int type = (buf[p] << 8) | buf[p + 1];
                    int rdlen = (buf[p + 8] << 8) | buf[p + 9];
                    p += 10;
                    if (type == 1 && rdlen == 4 && p + 4 <= n)
                        AddIp(r, new IPAddress(new byte[] { buf[p], buf[p + 1], buf[p + 2], buf[p + 3] }));
                    p += rdlen;
                }
            }
            catch (Exception) { }
            finally { if (s != null) try { s.Close(); } catch (Exception) { } }
            return r;
        }

        public static List<IPAddress> Resolve(string host)
        {
            DnsEntry stale = null;
            lock (Sync)
            {
                DnsEntry e;
                if (dnsCache.TryGetValue(host, out e))
                {
                    if ((DateTime.UtcNow - e.At).TotalSeconds < 240) return new List<IPAddress>(e.Ips);
                    stale = e;
                }
            }
            List<IPAddress> fresh = new List<IPAddress>();
            if (!NoNetworkDns)
            {
                List<IPAddress>[] rs = new List<IPAddress>[4];
                bool[] fin = new bool[4];
                string h = host;
                for (int i = 0; i < 4; i++)
                {
                    int k = i;
                    Thread t = new Thread(delegate()
                    {
                        List<IPAddress> x;
                        if (k == 0) x = DohQuery("https://8.8.8.8/resolve?name=" + h + "&type=A", false);
                        else if (k == 1) x = DohQuery("https://1.1.1.1/dns-query?name=" + h + "&type=A", true);
                        else if (k == 2) x = UdpDns("8.8.8.8", h);
                        else x = UdpDns("1.1.1.1", h);
                        lock (fin) { rs[k] = x; fin[k] = true; }
                    });
                    t.IsBackground = true;
                    t.Start();
                }
                Stopwatch sw = Stopwatch.StartNew();
                while (true)
                {
                    int done = 0;
                    bool any = false;
                    lock (fin)
                    {
                        for (int i = 0; i < 4; i++)
                        {
                            if (fin[i]) { done++; if (rs[i] != null && rs[i].Count > 0) any = true; }
                        }
                    }
                    if (done == 4) break;
                    if (any && sw.ElapsedMilliseconds > 700) break;
                    if (sw.ElapsedMilliseconds > 4800) break;
                    Thread.Sleep(20);
                }
                lock (fin)
                {
                    for (int i = 0; i < 4; i++)
                        if (fin[i] && rs[i] != null) for (int j = 0; j < rs[i].Count; j++) AddIp(fresh, rs[i][j]);
                }
            }
            List<IPAddress> result = new List<IPAddress>();
            for (int i = 0; i < fresh.Count && result.Count < 4; i++) AddIp(result, fresh[i]);
            string lg;
            lock (Sync) { lastGood.TryGetValue(host, out lg); }
            IPAddress lgIp;
            if (!string.IsNullOrEmpty(lg) && IPAddress.TryParse(lg, out lgIp)) AddIp(result, lgIp);
            if (fresh.Count == 0 && result.Count == 0 && stale != null) result = new List<IPAddress>(stale.Ips);
            if (fresh.Count > 0)
            {
                DnsEntry ne = new DnsEntry();
                ne.Ips = new List<IPAddress>(result);
                ne.At = DateTime.UtcNow;
                lock (Sync) { dnsCache[host] = ne; }
            }
            return result;
        }

        // ------------------------------------------------------------ lastgood + nen
        static void LoadLastGood()
        {
            try
            {
                string p = Path.Combine(DataDir, "lastgood.txt");
                if (!File.Exists(p)) return;
                foreach (string line in File.ReadAllLines(p))
                {
                    string[] f = line.Trim().Split(new char[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                    IPAddress ip;
                    if (f.Length == 2 && IPAddress.TryParse(f[1], out ip)) lastGood[f[0]] = f[1];
                }
            }
            catch (Exception) { }
        }

        static void SaveLastGood()
        {
            try
            {
                List<string> lines = new List<string>();
                lock (Sync)
                {
                    foreach (KeyValuePair<string, string> kv in lastGood) lines.Add(kv.Key + " " + kv.Value);
                    lastGoodDirty = false;
                }
                File.WriteAllLines(Path.Combine(DataDir, "lastgood.txt"), lines.ToArray());
            }
            catch (Exception) { }
        }

        static void MaintLoop()
        {
            List<string> known = new List<string>();
            try
            {
                string p = Path.Combine(DataDir, "hosts.txt");
                if (File.Exists(p))
                    foreach (string l in File.ReadAllLines(p))
                    {
                        string h = l.Trim().ToLowerInvariant();
                        if (h.Length > 0 && !h.StartsWith("#") && AllowRx.IsMatch(h)) known.Add(h);
                    }
            }
            catch (Exception) { }
            int tick = 0;
            while (running)
            {
                try
                {
                    if (tick == 0 || tick % 48 == 0)
                    {
                        for (int i = 0; i < known.Count && running; i++)
                        {
                            lock (Sync) { dnsCache.Remove(known[i]); }
                            Resolve(known[i]);
                        }
                    }
                    if (tick > 0 && tick % 12 == 0)
                    {
                        List<string> lines = new List<string>();
                        lock (Sync)
                        {
                            foreach (KeyValuePair<string, HostStat> kv in stats)
                            {
                                if (!kv.Value.Dirty) continue;
                                kv.Value.Dirty = false;
                                lines.Add("stat " + kv.Key + " ok=" + kv.Value.Ok + " fail=" + kv.Value.Fail + " mode=" + kv.Value.Mode);
                            }
                        }
                        for (int i = 0; i < lines.Count; i++) Log(lines[i]);
                        if (lastGoodDirty) SaveLastGood();
                    }
                }
                catch (Exception) { }
                for (int w = 0; w < 5 && running; w++) Thread.Sleep(1000);
                tick++;
            }
        }

        // ------------------------------------------------------------ probe (client TLS di qua relay)
        public static ProbeResult Probe(string host, string ip, int port, int timeoutMs)
        {
            ProbeResult pr = new ProbeResult();
            pr.Host = host;
            pr.Info = "";
            TcpClient c = null;
            try
            {
                c = new TcpClient();
                IAsyncResult ar = c.BeginConnect(ip, port, null, null);
                if (!ar.AsyncWaitHandle.WaitOne(timeoutMs)) { pr.Info = "relay khong phan hoi"; return pr; }
                c.EndConnect(ar);
                NetworkStream ns = c.GetStream();
                ns.ReadTimeout = timeoutMs;
                ns.WriteTimeout = timeoutMs;
                SslStream ssl = new SslStream(ns, false);
                ssl.AuthenticateAsClient(host, null, System.Security.Authentication.SslProtocols.Tls12, false);
                byte[] req = Encoding.ASCII.GetBytes("GET / HTTP/1.1\r\nHost: " + host + "\r\nUser-Agent: Valve/Steam HTTP Client 1.0\r\nConnection: close\r\n\r\n");
                ssl.Write(req, 0, req.Length);
                ssl.Flush();
                byte[] buf = new byte[64];
                int n = ssl.Read(buf, 0, buf.Length);
                string line = Encoding.ASCII.GetString(buf, 0, Math.Max(n, 0));
                Match m = Regex.Match(line, @"^HTTP/\d\.\d (\d{3})");
                if (m.Success) { pr.Ok = true; pr.Info = "HTTP " + m.Groups[1].Value; }
                else pr.Info = "TLS ok nhung khong co HTTP hop le";
            }
            catch (Exception ex)
            {
                Exception b = ex;
                while (b.InnerException != null) b = b.InnerException;
                pr.Info = b.Message;
            }
            finally { if (c != null) try { c.Close(); } catch (Exception) { } }
            if (pr.Ok)
            {
                pr.Mode = ModeOf(host);
                pr.Ip = IpOf(host);
            }
            else
            {
                string f = FailOf(host);
                if (f.Length > 0) pr.Info = f;
            }
            return pr;
        }

        public static ProbeResult[] ProbeAll(string[] hosts, string ip, int port, int timeoutMs)
        {
            ProbeResult[] res = new ProbeResult[hosts.Length];
            Thread[] ts = new Thread[hosts.Length];
            for (int i = 0; i < hosts.Length; i++)
            {
                int k = i;
                ts[i] = new Thread(delegate() { res[k] = Probe(hosts[k], ip, port, timeoutMs); });
                ts[i].IsBackground = true;
                ts[i].Start();
            }
            for (int i = 0; i < ts.Length; i++) ts[i].Join(timeoutMs + 20000);
            for (int i = 0; i < res.Length; i++)
            {
                if (res[i] == null)
                {
                    res[i] = new ProbeResult();
                    res[i].Host = hosts[i];
                    res[i].Info = "qua thoi gian cho";
                }
            }
            return res;
        }
    }
}
'@

# ------------------------------------------------------------
#  Tien ich chung
# ------------------------------------------------------------
function Get-TargetAdapters {
    $list = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')
    if (-not $list) {
        $list = @(Get-NetIPConfiguration | Where-Object IPv4DefaultGateway | ForEach-Object NetAdapter)
    }
    $list
}

function Get-SteamDir {
    $p = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if (-not $p) { $p = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath }
    if (-not $p) {
        $proc = Get-Process steam -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($proc -and $proc.Path) { $p = Split-Path $proc.Path }
    }
    if ($p) { $p = $p -replace '/', '\' }
    return $p
}

function Add-Unique($list, [string]$ip) {
    if ($ip -match '^\d+\.\d+\.\d+\.\d+$' -and $ip -notmatch '^(127\.|0\.)' -and -not $list.Contains($ip)) { $list.Add($ip) }
}

# Hoi DNS qua HTTPS (dung IP truc tiep nen khong phu thuoc DNS cua nha mang).
# -Only 'google' | 'cf' de chon 1 may chu. Tra ve @{ Ok = da hoi duoc hay chua; Ips = danh sach IPv4 }
function Resolve-Doh([string]$name, [switch]$All, [string]$Only = '') {
    $endpoints = @(
        @{ Name = 'google'; Url = "https://8.8.8.8/resolve?name=$name&type=A";    Headers = @{} },
        @{ Name = 'cf';     Url = "https://1.1.1.1/dns-query?name=$name&type=A"; Headers = @{ accept = 'application/dns-json' } }
    )
    if ($Only) { $endpoints = @($endpoints | Where-Object { $_.Name -eq $Only }) }
    $ok  = $false
    $acc = New-Object System.Collections.Generic.List[string]
    foreach ($e in $endpoints) {
        try {
            $r = Invoke-RestMethod -Uri $e.Url -Headers $e.Headers -TimeoutSec 6 -UseBasicParsing -ErrorAction Stop
            $ok = $true
            foreach ($a in @($r.Answer)) {
                if ($a -and $a.type -eq 1) { Add-Unique $acc ([string]$a.data) }
            }
            if (-not $All) { break }
        } catch { }
    }
    return @{ Ok = $ok; Ips = $acc.ToArray() }
}

# Thu ket noi TCP -> TLS (dung dung ten mien/SNI) -> HTTP toi mot IP:cong cu the.
function Test-TlsHttp([string]$ip, [string]$hostName, [int]$timeoutMs = 3000, [int]$port = 443) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($ip, $port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($timeoutMs)) {
            return @{ Ok = $false; Stage = 'tcp'; Msg = 'TCP het thoi gian cho (IP bi chan / mat goi)' }
        }
        try { $client.EndConnect($iar) } catch {
            return @{ Ok = $false; Stage = 'tcp'; Msg = 'TCP bi tu choi/reset (IP bi chan hoac relay khong chay)' }
        }
        $ns = $client.GetStream()
        $ns.ReadTimeout = $timeoutMs
        $ns.WriteTimeout = $timeoutMs
        $ssl = New-Object System.Net.Security.SslStream($ns, $false)
        try {
            $ssl.AuthenticateAsClient($hostName, $null, [System.Security.Authentication.SslProtocols]::Tls12, $false)
        } catch {
            return @{ Ok = $false; Stage = 'tls'; Msg = ('TCP duoc nhung bat tay TLS that bai (chan theo ten mien/SNI hoac gia mach): ' + $_.Exception.GetBaseException().Message) }
        }
        $req = [Text.Encoding]::ASCII.GetBytes("GET / HTTP/1.1`r`nHost: $hostName`r`nUser-Agent: Valve/Steam HTTP Client 1.0`r`nConnection: close`r`n`r`n")
        $ssl.Write($req, 0, $req.Length)
        $ssl.Flush()
        $buf = New-Object byte[] 64
        $n = $ssl.Read($buf, 0, $buf.Length)
        $line = [Text.Encoding]::ASCII.GetString($buf, 0, $n)
        if ($line -match '^HTTP/\d\.\d (\d{3})') {
            return @{ Ok = $true; Stage = 'ok'; Msg = ('HTTP ' + $Matches[1]) }
        }
        return @{ Ok = $false; Stage = 'http'; Msg = 'TLS duoc nhung khong nhan duoc phan hoi HTTP hop le' }
    } catch {
        return @{ Ok = $false; Stage = 'err'; Msg = $_.Exception.GetBaseException().Message }
    } finally {
        $client.Close()
    }
}

# ------------------------------------------------------------
#  Hien thi trang thai DNS
# ------------------------------------------------------------
function Show-DnsStatus {
    Write-Host "`n--- Card mang & DNS hien tai ---" -ForegroundColor Cyan
    $adapters = Get-TargetAdapters
    if (-not $adapters) {
        Write-Host '  Khong tim thay card mang nao dang ket noi.' -ForegroundColor Red
        return
    }
    foreach ($a in $adapters) {
        $v4 = (Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses -join ', '
        $v6 = (Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue).ServerAddresses -join ', '
        Write-Host "  $($a.Name)"
        Write-Host "    IPv4: $(if ($v4) { $v4 } else { '(trong)' })"
        Write-Host "    IPv6: $(if ($v6) { $v6 } else { '(trong)' })"
    }
    if (Get-Command Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue) {
        $doh = @(Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue | Where-Object { $_.AutoUpgrade })
        $txt = if ($doh) { ($doh.ServerAddress -join ', ') } else { 'chua bat' }
        Write-Host "  DNS ma hoa (DoH tu dong): $txt"
    } else {
        Write-Host '  DNS ma hoa (DoH): Windows nay khong ho tro (can Windows 11)'
    }
}

# ------------------------------------------------------------
#  Relay: trang thai
# ------------------------------------------------------------
function Test-RelayListening([int]$port = 443) {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $c.BeginConnect('127.0.0.1', $port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(1000)) { return $false }
        try { $c.EndConnect($iar); return $true } catch { return $false }
    } catch { return $false } finally { $c.Close() }
}

# Cac ten mien trong khoi SteamFix cua hosts dang tro ve 127.0.0.1 (= di qua relay)
function Get-RelayMapped {
    $out = New-Object System.Collections.Generic.List[string]
    $in = $false
    foreach ($l in @(Get-Content $HostsPath -ErrorAction SilentlyContinue)) {
        if ($l -like '# >>> SteamFix*') { $in = $true; continue }
        if ($l -like '# <<< SteamFix*') { $in = $false; continue }
        if ($in) {
            $t = ($l -replace '#.*$', '').Trim()
            if ($t -match '^127\.0\.0\.1\s+(\S+)$') { $out.Add($Matches[1].ToLower()) }
        }
    }
    return $out.ToArray()
}

function Show-RelayStatus {
    Write-Host "`n--- Relay Steam (v5) ---" -ForegroundColor Cyan
    $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    $mapped = @(Get-RelayMapped)
    if (-not $t -and $mapped.Count -eq 0) {
        Write-Host '  Chua cai relay. Chon [1] de cai (khuyen dung neu Steam hay mat CSS / avatar / -105).' -ForegroundColor Yellow
        return
    }
    $listen = Test-RelayListening $RelayPort
    Write-Host ("  Tac vu nen            : {0}" -f $(if ($t) { $t.State } else { 'KHONG CO' }))
    Write-Host ("  127.0.0.1:{0,-4}         : {1}" -f $RelayPort, $(if ($listen) { 'dang nghe' } else { 'KHONG nghe' }))
    Write-Host ("  127.0.0.1:80  (HTTP)  : {0}" -f $(if (Test-RelayListening 80) { 'dang nghe' } else { 'KHONG nghe' }))
    Write-Host ("  Ten mien tro ve relay : {0}" -f $mapped.Count)
    if ($mapped.Count -gt 0 -and -not $listen) {
        Write-Host '  [!!] Hosts dang tro ve relay nhung relay KHONG chay -> Steam web se loi. Chon [1] de cai lai hoac [4] de go.' -ForegroundColor Red
    }
}

# ------------------------------------------------------------
#  QUET: DNS + HTTPS that toi tung domain Steam (chi doc, khong sua gi)
# ------------------------------------------------------------
function Test-SteamConnection {
    Write-Host "`n--- Quet ket noi Steam (DNS + HTTPS) - chi doc, khong sua gi ---" -ForegroundColor Cyan
    try { Clear-DnsClientCache -ErrorAction Stop } catch { ipconfig /flushdns | Out-Null }

    $relaySet = @{}
    foreach ($m in @(Get-RelayMapped)) { $relaySet[$m] = $true }

    # 1) Phan giai DNS song song
    $dnsTasks = [ordered]@{}
    foreach ($h in $SteamHosts) { $dnsTasks[$h] = [System.Net.Dns]::GetHostAddressesAsync($h) }
    try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($dnsTasks.Values), 15000) } catch { }

    $results   = [ordered]@{}
    $httpTasks = [ordered]@{}
    $clients   = @()
    foreach ($h in $SteamHosts) {
        $t = $dnsTasks[$h]
        $isRelay = $relaySet.ContainsKey($h)
        $r = @{ Ips = @(); State = ''; Msg = ''; Relay = $isRelay }
        if ($t.Status -eq 'RanToCompletion') {
            $ips = @($t.Result)
            $r.Ips = $ips
            $bad = @($ips | Where-Object {
                [System.Net.IPAddress]::IsLoopback($_) -or
                $_.Equals([System.Net.IPAddress]::Any) -or
                $_.Equals([System.Net.IPAddress]::IPv6Any)
            })
            if ($bad.Count -gt 0 -and -not $isRelay) {
                $r.State = 'BLOCK'
            } elseif ($DnsOnlyHosts -contains $h) {
                $r.State = 'OKDNS'
            } else {
                $r.State = 'RESOLVED'
                $handler = New-Object System.Net.Http.HttpClientHandler
                $handler.AllowAutoRedirect = $false
                $c = New-Object System.Net.Http.HttpClient($handler)
                $c.Timeout = [TimeSpan]::FromSeconds(10)
                $c.DefaultRequestHeaders.UserAgent.ParseAdd('Valve/Steam HTTP Client 1.0')
                $clients += $c
                $httpTasks[$h] = $c.GetAsync("https://$h/", [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead)
            }
        } else {
            $r.State = 'NODNS'
        }
        $results[$h] = $r
    }

    # 2) Ket noi HTTPS song song
    if ($httpTasks.Count -gt 0) {
        try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($httpTasks.Values), 15000) } catch { }
        foreach ($h in @($httpTasks.Keys)) {
            $t = $httpTasks[$h]
            if ($t.Status -eq 'RanToCompletion') {
                $results[$h].State = 'OK'
                $results[$h].Msg = 'HTTP ' + [int]$t.Result.StatusCode
                $t.Result.Dispose()
            } else {
                $results[$h].State = 'NOCONN'
                $results[$h].Msg = if ($t.Exception) { $t.Exception.GetBaseException().Message } else { 'qua thoi gian cho (timeout)' }
            }
        }
    }
    foreach ($c in $clients) { $c.Dispose() }

    # 3) Domain khong phan giai duoc -> doi chieu DNS ma hoa: bi chan hay khong ton tai
    foreach ($h in $SteamHosts) {
        if ($results[$h].State -eq 'NODNS') {
            $d = Resolve-Doh $h
            if ($d.Ok) {
                if ($d.Ips.Count -eq 0) { $results[$h].State = 'GONE' }
                else { $results[$h].State = 'DNSFAIL'; $results[$h].Ips = $d.Ips }
            }
        }
    }

    # 4) Domain (khong qua relay) ket noi that bai -> chan doan chinh xac loi o buoc nao (TCP / TLS / HTTP)
    $needDiag = @($SteamHosts | Where-Object { $results[$_].State -eq 'NOCONN' -and -not $results[$_].Relay })
    if ($needDiag.Count -gt 0) {
        Write-Host "  Dang chan doan chi tiet $($needDiag.Count) domain loi..." -ForegroundColor DarkGray
        foreach ($h in $needDiag) {
            $v4 = @($results[$h].Ips | Where-Object { "$_" -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1)
            if ($v4.Count -eq 0) {
                $results[$h].Msg = 'chi co IPv6 (khong chan doan chi tiet duoc): ' + $results[$h].Msg
                continue
            }
            $p = Test-TlsHttp ([string]$v4[0]) $h 3000
            if ($p.Ok) {
                $results[$h].State = 'OK'
                $results[$h].Msg = $p.Msg + ' (kiem tra truc tiep)'
            } else {
                $results[$h].Msg = $p.Msg
            }
        }
    }

    # 5) In ket qua + ghi lai danh sach domain loi
    $nOk = 0; $nBad = 0; $dnsBad = 0; $connBad = 0; $relayBad = 0
    $failList = New-Object System.Collections.ArrayList
    foreach ($h in $SteamHosts) {
        $r = $results[$h]
        $ipTxt = (@($r.Ips | Select-Object -First 2) -join ', ')
        $tag = if ($r.Relay) { ' [relay]' } else { '' }
        switch ($r.State) {
            'OK'      { $nOk++;  Write-Host ("  [OK]        {0,-38} -> {1} ({2}){3}" -f $h, $ipTxt, $r.Msg, $tag) -ForegroundColor Green }
            'OKDNS'   { $nOk++;  Write-Host ("  [OK]        {0,-38} -> {1} (chi kiem tra DNS)" -f $h, $ipTxt) -ForegroundColor Green }
            'GONE'    { Write-Host ("  [BO QUA]    {0,-38} (domain khong ton tai, khong phai loi)" -f $h) -ForegroundColor DarkGray }
            'BLOCK'   { $nBad++; $dnsBad++;  Write-Host ("  [BI CHAN]   {0,-38} -> {1}" -f $h, ($r.Ips -join ', ')) -ForegroundColor Red }
            'DNSFAIL' { $nBad++; $dnsBad++;  Write-Host ("  [LOI DNS]   {0,-38} DNS hien tai khong tra loi (DNS ma hoa thi duoc: {1})" -f $h, $ipTxt) -ForegroundColor Red }
            'NODNS'   { $nBad++; $dnsBad++;  Write-Host ("  [LOI DNS]   {0,-38} khong phan giai duoc" -f $h) -ForegroundColor Red }
            'NOCONN'  { $nBad++
                        if ($r.Relay) { $relayBad++ } else { $connBad++ }
                        Write-Host ("  [LOI NOI]   {0,-38} -> {1}{2}" -f $h, $ipTxt, $tag) -ForegroundColor Red
                        Write-Host ("              {0}" -f $r.Msg) -ForegroundColor DarkYellow }
        }
        if ($r.State -in @('BLOCK', 'DNSFAIL', 'NODNS', 'NOCONN') -and ($DnsOnlyHosts -notcontains $h)) {
            [void]$failList.Add([pscustomobject]@{ Host = $h; Ips = @($r.Ips) })
        }
    }
    $global:SteamFailedHosts = $failList.ToArray()
    $global:SteamScanDone = $true

    Write-Host ("`n  Tong ket: {0} domain OK, {1} domain LOI." -f $nOk, $nBad)
    if ($nBad -eq 0) {
        Write-Host '  => Steam ket noi binh thuong.' -ForegroundColor Green
        return $true
    }
    if ($dnsBad -gt 0) {
        Write-Host '  => Co domain bi chan/gia mach/khong phan giai duoc bang DNS. Chon [1] (relay khong phu thuoc DNS cua may).' -ForegroundColor Yellow
    }
    if ($connBad -gt 0) {
        Write-Host '  => DNS dung nhung HTTPS bi RESET/cat giua chung (dau hieu loc theo ten mien SNI).' -ForegroundColor Yellow
        Write-Host '     Chon [1] de cai relay vuot chan SNI, hoac [3] de kiem chung kieu chia nho nao qua duoc.' -ForegroundColor Yellow
    }
    if ($relayBad -gt 0) {
        Write-Host '  => Co domain DA di qua relay nhung van loi: xem [10] (log relay) / chay [3] (lab) de biet nguyen nhan.' -ForegroundColor Yellow
    }
    return $false
}

# ------------------------------------------------------------
#  File hosts - AN TOAN: chi dong vao dong cua tool / dong chan Steam
# ------------------------------------------------------------
function Remove-FixBlock($lines) {
    $out = New-Object System.Collections.Generic.List[string]
    $inBlock = $false
    foreach ($l in $lines) {
        if ($l -like '# >>> SteamFix*') {
            $inBlock = $true
            # bo dung 1 dong trong ma tool da them truoc khoi
            if ($out.Count -gt 0 -and [string]::IsNullOrWhiteSpace($out[$out.Count - 1])) { $out.RemoveAt($out.Count - 1) }
            continue
        }
        if ($l -like '# <<< SteamFix*') { $inBlock = $false; continue }
        if (-not $inBlock) { $out.Add([string]$l) }
    }
    return $out.ToArray()
}

function Test-SteamBlockLine([string]$line) {
    $t = ($line -replace '#.*$', '').Trim()
    if (-not $t) { return $false }
    $parts = @($t -split '\s+')
    if ($parts.Count -lt 2) { return $false }
    if ($parts[0] -notmatch '^(127\.\d+\.\d+\.\d+|0\.0\.0\.0|::1?|0:0:0:0:0:0:0:[01])$') { return $false }
    foreach ($n in $parts[1..($parts.Count - 1)]) {
        if ($n -match $SteamDomainRegex) { return $true }
    }
    return $false
}

# Ghi hosts co sao luu + doc lai kiem tra; sai la tu khoi phuc ban sao luu
function Write-HostsSafe([string[]]$newLines, [string[]]$preserved) {
    if (Test-HostsDamaged @(Get-Content $HostsPath -ErrorAction SilentlyContinue)) {
        throw 'File hosts dang bi hong (co dong qua dai). Hay khoi phuc tu ban sao luu truoc (mo lai tool, tool se de nghi).'
    }
    $backup = "$HostsPath.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item $HostsPath $backup -ErrorAction Stop
    try {
        [System.IO.File]::WriteAllLines($HostsPath, $newLines)
        $after = @(Remove-FixBlock @(Get-Content $HostsPath -ErrorAction Stop))
        if (($after -join "`n") -ne ($preserved -join "`n")) {
            throw 'Noi dung hosts sau khi ghi khong khop ban goc'
        }
    } catch {
        Copy-Item $backup $HostsPath -Force -ErrorAction SilentlyContinue
        throw
    }
    return $backup
}

function Repair-HostsFile {
    Write-Host "`n--- Kiem tra file hosts ---" -ForegroundColor Cyan
    $lines = @(Get-Content $HostsPath -ErrorAction SilentlyContinue)
    $active = @(Remove-FixBlock $lines | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' }).Count
    $inBlock = $false
    $hits = New-Object System.Collections.Generic.List[string]
    foreach ($l in $lines) {
        if ($l -like '# >>> SteamFix*') { $inBlock = $true; continue }
        if ($l -like '# <<< SteamFix*') { $inBlock = $false; continue }
        if (-not $inBlock -and (Test-SteamBlockLine $l)) { $hits.Add($l) }
    }

    if ($hits.Count -eq 0) {
        Write-Host "  Khong co dong nao dang chan/chuyen huong Steam ve 127.0.0.1 / 0.0.0.0." -ForegroundColor Green
        Write-Host "  $active dong hosts dang hoat dong cua ban: tool KHONG dong vao." -ForegroundColor Green
        return
    }

    Write-Host '[!] Cac dong sau DANG chan/chuyen huong ten mien Steam:' -ForegroundColor Yellow
    foreach ($h in $hits) { Write-Host "    $h" -ForegroundColor Yellow }
    Write-Host "  Tool chi them dau # vao DUNG cac dong tren. $($active - $hits.Count) dong khac cua ban giu nguyen." -ForegroundColor Cyan
    $ans = Read-Host 'Vo hieu hoa rieng cac dong Steam o tren? (Y/N)'
    if ($ans -notmatch '^[yYcC]') { return }

    try {
        $backup = "$HostsPath.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Copy-Item $HostsPath $backup -ErrorAction Stop
        $inBlock = $false
        $new = foreach ($l in $lines) {
            if ($l -like '# >>> SteamFix*') { $inBlock = $true;  $l; continue }
            if ($l -like '# <<< SteamFix*') { $inBlock = $false; $l; continue }
            if (-not $inBlock -and (Test-SteamBlockLine $l)) { "# $l" } else { $l }
        }
        [System.IO.File]::WriteAllLines($HostsPath, [string[]]@($new))
        if (@(Get-Content $HostsPath).Count -ne $lines.Count) {
            Copy-Item $backup $HostsPath -Force
            throw 'So dong thay doi bat thuong, da khoi phuc ban sao luu.'
        }
        Write-Host "  [OK] Da vo hieu hoa. Ban sao luu: $backup" -ForegroundColor Green
    } catch {
        Write-Host "  [LOI] Khong sua duoc file hosts: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ------------------------------------------------------------
#  Phat hien + khoi phuc file hosts bi hong
#  (loi cua ban v2: gop ca file thanh 1 dong dai bat dau bang # -> moi dong ben trong mat tac dung)
# ------------------------------------------------------------
function Test-HostsDamaged($lines) {
    foreach ($l in $lines) { if ($l -and $l.Length -gt 400) { return $true } }
    return $false
}

function Get-HostsBackups {
    $dir = Split-Path $HostsPath
    $files = @(Get-ChildItem $dir -Filter 'hosts.*' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^hosts\.(steamfix-goc|bak-)' })
    foreach ($f in $files) {
        $ls = @(Get-Content $f.FullName -ErrorAction SilentlyContinue)
        [pscustomobject]@{
            Path    = $f.FullName
            Name    = $f.Name
            Time    = $f.LastWriteTime
            Active  = @(Remove-FixBlock $ls | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' }).Count
            Healthy = -not (Test-HostsDamaged $ls)
        }
    }
}

function Repair-DamagedHosts {
    $lines = @(Get-Content $HostsPath -ErrorAction SilentlyContinue)
    if (-not (Test-HostsDamaged $lines)) { return $false }

    Write-Host "`n[!!] FILE HOSTS BI HONG: co dong dai bat thuong (nhieu dong bi gop thanh 1 dong bat dau bang #)." -ForegroundColor Red
    Write-Host '     Hau qua: cac dong hosts cua ban nam trong dong do deu thanh ghi chu, KHONG con tac dung.' -ForegroundColor Red
    Write-Host '     (Do loi cua ban v2 khi ghim hosts. Tu v3 tro di da sua va co chot chan.)' -ForegroundColor Red

    $cands = @(Get-HostsBackups | Where-Object { $_.Healthy -and $_.Active -gt 0 } |
        Sort-Object @{ Expression = { $_.Name -ne 'hosts.steamfix-goc' } }, @{ Expression = { $_.Time }; Descending = $true })
    if ($cands.Count -eq 0) {
        Write-Host '  Khong tim thay ban sao luu hosts nao con tot trong thu muc drivers\etc.' -ForegroundColor Yellow
        Write-Host '  Tool se KHONG ghi them gi vao hosts cho den khi file duoc sua. Noi dung goc van nam trong dong dai do' -ForegroundColor Yellow
        Write-Host '  (hoac trong log cu ban da gui) nen van khoi phuc duoc - hay nho tro giup.' -ForegroundColor Yellow
        return $true
    }

    Write-Host "`n  Cac ban sao luu con tot (uu tien ban goc do v2 tao):" -ForegroundColor Cyan
    $i = 0
    foreach ($c in $cands) {
        $i++
        Write-Host ("    [{0}] {1}   ({2:yyyy-MM-dd HH:mm}, {3} dong dang hoat dong)" -f $i, $c.Name, $c.Time, $c.Active)
    }
    $sel = Read-Host '  Chon so ban sao luu de khoi phuc (Enter = bo qua)'
    if ($sel -notmatch '^\d+$' -or [int]$sel -lt 1 -or [int]$sel -gt $cands.Count) {
        Write-Host '  Bo qua. Hosts van dang hong; tool se khong ghi them gi vao hosts.' -ForegroundColor Yellow
        return $true
    }
    $pick = $cands[[int]$sel - 1]
    try {
        $keep = "$HostsPath.bak-hong-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Copy-Item $HostsPath $keep -ErrorAction Stop
        Copy-Item $pick.Path $HostsPath -Force -ErrorAction Stop
        if (Test-HostsDamaged @(Get-Content $HostsPath -ErrorAction SilentlyContinue)) {
            Copy-Item $keep $HostsPath -Force
            throw 'Ban sao luu nay van loi, da hoan tac.'
        }
        try { Clear-DnsClientCache } catch { }
        Write-Host "  [OK] Da khoi phuc hosts tu $($pick.Name). Ban hong cu duoc giu o: $keep" -ForegroundColor Green
    } catch {
        Write-Host "  [LOI] $($_.Exception.Message)" -ForegroundColor Red
    }
    return $true
}

# ------------------------------------------------------------
#  Chan doan: bi chan theo IP hay theo TEN MIEN (SNI)?
#  Bat tay TLS "long leo": khong gui du lieu, khong kiem tra chung chi, chi xem co bi RESET khong.
# ------------------------------------------------------------
function Test-Handshake([string]$ip, [string]$sni, [int]$timeoutMs = 4000) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($ip, 443, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($timeoutMs)) { return 'TCP-TIMEOUT' }
        try { $client.EndConnect($iar) } catch { return 'TCP-REFUSED' }
        $ns = $client.GetStream()
        $ns.ReadTimeout = $timeoutMs
        $ns.WriteTimeout = $timeoutMs
        $cb = [System.Net.Security.RemoteCertificateValidationCallback]{ param($snd, $cert, $chain, $err) $true }
        $ssl = New-Object System.Net.Security.SslStream($ns, $false, $cb)
        try {
            $ssl.AuthenticateAsClient($sni, $null, [System.Security.Authentication.SslProtocols]::Tls12, $false)
            return 'OK'
        } catch {
            $be = $_.Exception.GetBaseException()
            if ($be -is [System.Net.Sockets.SocketException]) {
                $code = [string]$be.SocketErrorCode
                if ($code -in @('ConnectionReset', 'ConnectionAborted')) { return 'RESET' }
                if ($code -eq 'TimedOut') { return 'TIMEOUT' }
            }
            return ('LOI: ' + $be.Message)
        }
    } catch {
        return ('LOI: ' + $_.Exception.GetBaseException().Message)
    } finally {
        $client.Close()
    }
}

function Invoke-SniDiagnosis {
    Write-Host "`n--- Chan doan: bi chan theo IP hay theo TEN MIEN (SNI)? (chi doc, khong sua gi) ---" -ForegroundColor Cyan
    # Lay IP that qua DNS ma hoa (khong bi anh huong boi hosts/relay). Google co the tra ve cache NOI DIA (de qua),
    # Cloudflare tra ve IP toan cau -> dung Cloudflare lam IP tham chieu.
    $fa = $null; $ak = $null
    $d1 = Resolve-Doh 'store.fastly.steamstatic.com' -Only 'cf'
    if ($d1.Ips.Count -gt 0) { $fa = $d1.Ips[0] }
    $d2 = Resolve-Doh 'cdn.akamai.steamstatic.com' -Only 'cf'
    if ($d2.Ips.Count -gt 0) { $ak = $d2.Ips[0] }
    if (-not $fa -or -not $ak) {
        Write-Host '  [LOI] Khong lay duoc IP tham chieu qua DNS ma hoa (8.8.8.8 / 1.1.1.1 co the bi chan).' -ForegroundColor Red
        return
    }
    Write-Host "  IP Fastly tham chieu: $fa   |   IP Akamai tham chieu: $ak" -ForegroundColor DarkGray

    $tests = @(
        @{ Id = 'A1'; Ip = $fa; Sni = 'store.fastly.steamstatic.com'; Note = 'IP Fastly + ten Steam' },
        @{ Id = 'A2'; Ip = $fa; Sni = 'www.python.org';               Note = 'IP Fastly + ten trung tinh (cung nha Fastly)' },
        @{ Id = 'A3'; Ip = $fa; Sni = 'example.com';                  Note = 'IP Fastly + ten trung tinh khac' },
        @{ Id = 'B1'; Ip = $ak; Sni = 'cdn.akamai.steamstatic.com';   Note = 'IP Akamai + ten Steam-Akamai' },
        @{ Id = 'B2'; Ip = $ak; Sni = 'store.fastly.steamstatic.com'; Note = 'IP Akamai + ten Steam-Fastly' },
        @{ Id = 'B3'; Ip = $ak; Sni = 'avatars.steamstatic.com';      Note = 'IP Akamai + ten avatar' },
        @{ Id = 'B4'; Ip = $ak; Sni = 'help.steampowered.com';        Note = 'IP Akamai + help.steampowered.com' },
        @{ Id = 'B5'; Ip = $ak; Sni = 'www.python.org';               Note = 'IP Akamai + ten trung tinh' }
    )
    $res = @{}
    foreach ($t in $tests) {
        $r = Test-Handshake $t.Ip $t.Sni 4000
        $res[$t.Id] = $r
        $col = if ($r -eq 'OK') { 'Green' } elseif ($r -eq 'RESET') { 'Red' } else { 'Yellow' }
        Write-Host ("  [{0}] {1,-46} => {2}" -f $t.Id, $t.Note, $r) -ForegroundColor $col
    }

    $sniHit    = ($res['B2'] -eq 'RESET' -or $res['B3'] -eq 'RESET' -or $res['B4'] -eq 'RESET') -and ($res['B5'] -eq 'OK')
    $sniFastly = ($res['A1'] -eq 'RESET' -and ($res['A2'] -eq 'OK' -or $res['A3'] -eq 'OK'))
    $ipFastly  = ($res['A1'] -eq 'RESET' -and $res['A2'] -eq 'RESET' -and $res['A3'] -eq 'RESET')

    Write-Host ''
    if ($sniHit -or $sniFastly) {
        Write-Host '  KET LUAN: ket noi bi RESET khi bat tay TLS co TEN MIEN Steam (SNI); cung IP nhung ten khac thi qua duoc.' -ForegroundColor Yellow
        Write-Host '            => thiet bi tren duong truyen (nha mang) dang loc theo ten mien.' -ForegroundColor Yellow
        Write-Host '            DNS / hosts / doi IP khong sua duoc. Cach sua tren may: RELAY chia nho ClientHello ([1]).' -ForegroundColor Yellow
    } elseif ($ipFastly) {
        Write-Host '  KET LUAN: ca dai IP Fastly bi RESET bat ke ten mien -> chan theo dai IP. Chay [3] (lab) de xem relay co vuot duoc khong.' -ForegroundColor Yellow
    } else {
        Write-Host '  KET QUA CHUA RO RANG (mang chap chon hoac loc khong theo quy luat). Chay [3] (lab) de co bang chung ro hon.' -ForegroundColor Yellow
    }
    Write-Host '  Doi chung nhanh: noi may vao hotspot 4G (nha mang khac). Steam binh thuong -> chac chan do nha mang, khong phai loi may.' -ForegroundColor Cyan
}

# ------------------------------------------------------------
#  RELAY: bien dich, thu, cai dat, go
# ------------------------------------------------------------
function Test-HttpPlain([string]$hostName) {
    $hd = New-Object System.Net.Http.HttpClientHandler
    $hd.AllowAutoRedirect = $false
    $c = New-Object System.Net.Http.HttpClient($hd)
    $c.Timeout = [TimeSpan]::FromSeconds(12)
    try {
        $r = $c.GetAsync("http://$hostName/").GetAwaiter().GetResult()
        $code = [int]$r.StatusCode
        $r.Dispose()
        return @{ Ok = $true; Msg = "HTTP $code" }
    } catch {
        return @{ Ok = $false; Msg = $_.Exception.GetBaseException().Message }
    } finally {
        $c.Dispose()
    }
}

function Initialize-RelayType {
    if ('SteamFix.Relay' -as [type]) { return $true }
    try {
        Add-Type -TypeDefinition $RelayCs -ReferencedAssemblies @('System.dll') -ErrorAction Stop
        return $true
    } catch {
        Write-Host "  [LOI] Khong bien dich duoc relay: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Chay relay ngay trong tien trinh nay (cong thu), thu HTTPS that toi tung ten mien qua relay.
# -Mode: -1 = tu dong thu cac kieu; 0..3 = ep 1 kieu (tcp-sni, tcp-early, rec-sni, plain)
function Invoke-RelayProbe([string[]]$hosts, [int]$Mode = -1) {
    if (-not (Initialize-RelayType)) { return $null }
    [SteamFix.Relay]::ForceMode = $Mode
    [SteamFix.Relay]::HttpPort = 0
    try {
        [SteamFix.Relay]::Start('127.0.0.1', $ProbePort, $DataDir)
    } catch {
        Write-Host "  [LOI] Khong mo duoc relay thu o cong ${ProbePort}: $($_.Exception.Message)" -ForegroundColor Red
        [SteamFix.Relay]::ForceMode = -1
        return $null
    }
    try {
        return [SteamFix.Relay]::ProbeAll($hosts, '127.0.0.1', $ProbePort, 20000)
    } finally {
        [SteamFix.Relay]::Stop()
        [SteamFix.Relay]::ForceMode = -1
    }
}

function Get-RelayPids {
    try {
        return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                 Where-Object { $_.CommandLine -like '*SteamFix*relay.ps1*' } | ForEach-Object { [int]$_.ProcessId })
    } catch { return @() }
}

function Stop-RelayProcesses {
    try { Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue } catch { }
    try {
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like '*SteamFix*relay.ps1*' } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    } catch { }
    Start-Sleep -Milliseconds 700
}

function Remove-RelayHosts([switch]$Quiet) {
    if (-not $Quiet) { Write-Host "`n--- Go khoi SteamFix khoi file hosts ---" -ForegroundColor Cyan }
    try {
        $lines = @(Get-Content $HostsPath -ErrorAction SilentlyContinue)
        $clean = @(Remove-FixBlock $lines)
        if ($clean.Count -eq $lines.Count) {
            if (-not $Quiet) { Write-Host '  Khong co khoi SteamFix nao trong hosts.' -ForegroundColor Yellow }
            return
        }
        $backup = Write-HostsSafe ([string[]]$clean) ([string[]]$clean)
        try { Clear-DnsClientCache } catch { }
        if (-not $Quiet) { Write-Host "  [OK] Da go. Cac dong khac cua ban giu nguyen. Ban sao luu: $backup" -ForegroundColor Green }
    } catch {
        Write-Host "  [LOI] $($_.Exception.Message)" -ForegroundColor Red
    }
}

# May chu TAI GAME (HTTPS 443): cache theo vung (cacheN-hkg1 / cacheN-sgp1), steampipe..., cong them ten da thay trong content_log.
# Ten khong ton tai se tu bi bo qua o buoc thu.
function Get-ContentHostCandidates {
    $set = New-Object System.Collections.Generic.List[string]
    foreach ($f in @('steampipe.akamaized.net', 'fastly.cdn.steampipe.steamcontent.com',
                     'akamai.cdn.steampipe.steamcontent.com', 'cloudflare.cdn.steampipe.steamcontent.com')) { $set.Add($f) }
    foreach ($loc in @('hkg1', 'sgp1')) {
        for ($i = 1; $i -le 12; $i++) { $set.Add("cache$i-$loc.steamcontent.com") }
    }
    $steam = Get-SteamDir
    if ($steam) {
        $log = Join-Path $steam 'logs\content_log.txt'
        if (Test-Path $log) {
            $txt = (@(Get-Content $log -Tail 3000 -ErrorAction SilentlyContinue)) -join "`n"
            foreach ($m in [regex]::Matches($txt, '(?i)\b[a-z0-9-]+(?:\.[a-z0-9-]+)*\.steamcontent\.com\b|\bsteampipe[a-z0-9.-]*\.akamaized\.net\b')) {
                $v = $m.Value.ToLower()
                if (-not $set.Contains($v)) { $set.Add($v) }
            }
        }
    }
    return @($set | Select-Object -First 90)
}

function Install-Relay {
    Write-Host "`n--- Cai RELAY Steam (chia nho TLS ClientHello de vuot loc SNI - khong can VPN) ---" -ForegroundColor Cyan
    if (Test-HostsDamaged @(Get-Content $HostsPath -ErrorAction SilentlyContinue)) {
        Write-Host '  [DUNG] File hosts dang bi hong. Thoat tool, mo lai de khoi phuc truoc.' -ForegroundColor Red
        return $false
    }
    if (-not (Initialize-RelayType)) { return $false }
    $cand = @($RelayHosts) + @(Get-ContentHostCandidates)

    # 0) KHONG dung vao ban dang chay (relay + hosts) cho toi khi nguoi dung dong y o buoc ghi.
    try { Clear-DnsClientCache } catch { }
    $mine = @(Get-RelayPids)

    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $RelayPort -ErrorAction SilentlyContinue)
    $exact = @($listeners | Where-Object { $_.LocalAddress -eq '127.0.0.1' -and ($mine -notcontains $_.OwningProcess) })
    $wild  = @($listeners | Where-Object { $_.LocalAddress -in @('0.0.0.0', '::') -and ($mine -notcontains $_.OwningProcess) })
    foreach ($b in $exact) {
        $pn = (Get-Process -Id $b.OwningProcess -ErrorAction SilentlyContinue).ProcessName
        Write-Host "  [DUNG] Cong 127.0.0.1:$RelayPort dang bi chiem boi '$pn' (PID $($b.OwningProcess)). Tat chuong trinh do roi chay lai." -ForegroundColor Red
    }
    if ($exact.Count -gt 0) { return $false }
    foreach ($b in $wild) {
        $pn = (Get-Process -Id $b.OwningProcess -ErrorAction SilentlyContinue).ProcessName
        Write-Host "  [!] Cong $RelayPort dang duoc '$pn' (PID $($b.OwningProcess)) nghe tren moi dia chi. Van thu cai; neu relay khong nghe duoc, hay tat chuong trinh do." -ForegroundColor Yellow
    }

    # 1) Thu muc du lieu (chi SYSTEM + Administrators duoc ghi - relay chay bang SYSTEM)
    if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }
    & icacls.exe $DataDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null

    # 2) Gieo IP du phong tu DNS cua Windows (chi them ten chua co trong lastgood.txt)
    Write-Host '  Dang gieo IP du phong tu DNS cua may...' -ForegroundColor DarkGray
    $lgPath = Join-Path $DataDir 'lastgood.txt'
    $have = @{}
    if (Test-Path $lgPath) {
        foreach ($l in @(Get-Content $lgPath -ErrorAction SilentlyContinue)) {
            $f = @($l.Trim() -split '\s+')
            if ($f.Count -eq 2) { $have[$f[0]] = $f[1] }
        }
    }
    $dnsTasks = [ordered]@{}
    foreach ($h in $cand) { $dnsTasks[$h] = [System.Net.Dns]::GetHostAddressesAsync($h) }
    try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($dnsTasks.Values), 12000) } catch { }
    foreach ($h in $cand) {
        $t = $dnsTasks[$h]
        if ($t.Status -eq 'RanToCompletion' -and -not $have.ContainsKey($h)) {
            $a = @($t.Result | Where-Object { $_.AddressFamily -eq 'InterNetwork' -and -not [System.Net.IPAddress]::IsLoopback($_) } | Select-Object -First 1)
            if ($a.Count -gt 0) { $have[$h] = [string]$a[0] }
        }
    }
    $seedLines = @($have.Keys | ForEach-Object { "$_ $($have[$_])" })
    [IO.File]::WriteAllLines($lgPath, [string[]]$seedLines)

    # 3) Thu HTTPS that toi tung ten mien QUA RELAY (tu dong chon kieu chia nho)
    Write-Host "  Dang thu $($cand.Count) ten mien qua relay thu (tu dong thu cac kieu chia nho)..." -ForegroundColor DarkGray
    $res = Invoke-RelayProbe @($cand) -Mode -1
    if (-not $res) { return $false }

    $okHosts = New-Object System.Collections.Generic.List[string]
    $nFail = 0; $nNoDns = 0
    foreach ($r in $res) {
        if ($r.Ok) {
            $okHosts.Add($r.Host)
            Write-Host ("  [OK]   {0,-38} {1,-10} qua {2} ({3})" -f $r.Host, $r.Mode, $r.Ip, $r.Info) -ForegroundColor Green
        } elseif ($r.Info -like 'khong phan giai*') {
            $nNoDns++
            Write-Host ("  [-]    {0,-38} khong co IP (ten mien khong ton tai / DNS cong cong bi chan)" -f $r.Host) -ForegroundColor DarkGray
        } else {
            $nFail++
            Write-Host ("  [LOI]  {0,-38} {1}" -f $r.Host, $r.Info) -ForegroundColor Red
        }
    }
    if ($okHosts.Count -eq 0) {
        Write-Host "`n  [!] Khong ten mien nao qua duoc, ke ca khi chia nho ClientHello." -ForegroundColor Red
        if ($nNoDns -gt ($cand.Count / 2)) {
            Write-Host '      Phan lon la "khong co IP": relay khong hoi duoc DNS cong cong (8.8.8.8 / 1.1.1.1 bi chan?). Thu mang khac / hotspot 4G.' -ForegroundColor Yellow
        } else {
            Write-Host '      Bo loc cua nha mang khong bi chia nho vuot duoc (hoac chan theo dai IP). Chay [3] (lab) de xem chi tiet;' -ForegroundColor Yellow
            Write-Host '      neu van het cach thi can tunnel (Cloudflare WARP / VPN) khi dung Steam.' -ForegroundColor Yellow
        }
        return $false
    }
    Write-Host ("`n  Ket qua: {0} ten mien qua duoc relay, {1} loi, {2} khong co IP." -f $okHosts.Count, $nFail, $nNoDns) -ForegroundColor Cyan
    if ($nFail -gt 0) { Write-Host '  Ten mien LOI se khong bi dong vao hosts (giu nguyen nhu cu).' -ForegroundColor DarkGray }

    Write-Host "`n  Se: (a) cai tac vu nen '$TaskName' (chay bang SYSTEM, tu mo khi bat may), nghe 127.0.0.1:$RelayPort (HTTPS) va :80 (HTTP)" -ForegroundColor Cyan
    Write-Host "      (b) THEM $($okHosts.Count) dong '127.0.0.1 <ten mien>' vao khoi SteamFix rieng trong hosts (co sao luu, dong khac giu nguyen)." -ForegroundColor Cyan
    $ans = Read-Host '  Dong y? (Y/N)'
    if ($ans -notmatch '^[yYcC]') { Write-Host '  Da huy, khong thay doi gi (relay + hosts dang chay van giu nguyen).'; return $false }

    # Chi tu day moi dung vao ban dang chay: dung relay cu, go khoi hosts cu, roi cai ban moi
    Stop-RelayProcesses
    Remove-RelayHosts -Quiet
    try { Clear-DnsClientCache } catch { }

    # 4) Ghi file relay + dang ky tac vu nen
    [IO.File]::WriteAllLines((Join-Path $DataDir 'hosts.txt'), [string[]]@($okHosts))
    $relayScript = @"
`$ErrorActionPreference = 'Stop'
try {
`$src = @'
$($RelayCs.TrimEnd())
'@
Add-Type -TypeDefinition `$src -ReferencedAssemblies 'System.dll'
[SteamFix.Relay]::Run('127.0.0.1', $RelayPort, '$DataDir')
} catch {
    [IO.File]::AppendAllText((Join-Path '$DataDir' 'relay-error.log'), ((Get-Date -Format s) + ' ' + `$_.Exception.ToString() + "``r``n"))
    exit 1
}
"@
    [IO.File]::WriteAllText($RelayPs1, $relayScript, (New-Object System.Text.UTF8Encoding($false)))

    try {
        $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$RelayPs1`""
        $trg = @((New-ScheduledTaskTrigger -AtStartup), (New-ScheduledTaskTrigger -AtLogOn))
        $pri = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
                   -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName $TaskName -Action $act -Trigger $trg -Principal $pri -Settings $set -Force -ErrorAction Stop | Out-Null
        Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    } catch {
        Write-Host "  [LOI] Khong tao/chay duoc tac vu nen: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }

    Write-Host '  Dang cho relay khoi dong (bien dich lan dau mat vai giay)...' -ForegroundColor DarkGray
    $up = $false
    for ($i = 0; $i -lt 30; $i++) {
        if (Test-RelayListening $RelayPort) { $up = $true; break }
        Start-Sleep -Milliseconds 1000
    }
    if (-not $up) {
        Write-Host "  [LOI] Relay khong nghe duoc 127.0.0.1:$RelayPort. KHONG ghi hosts (tranh lam Steam hong)." -ForegroundColor Red
        foreach ($lf in @('relay-error.log', 'relay.log')) {
            $p = Join-Path $DataDir $lf
            if (Test-Path $p) { Write-Host "  --- $lf (cuoi) ---" -ForegroundColor DarkGray; Get-Content $p -Tail 8 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkYellow } }
        }
        return $false
    }
    Write-Host '  [OK] Relay dang chay.' -ForegroundColor Green

    # 5) Ghi hosts (them khoi SteamFix moi; khoi cu da duoc go o buoc 0)
    try {
        $lines = @(Get-Content $HostsPath -ErrorAction SilentlyContinue)
        $clean = @(Remove-FixBlock $lines)
        $entries = @($okHosts | ForEach-Object { "127.0.0.1 $_" })
        $new = $clean + @('', $HostsBegin) + $entries + @($HostsEnd)
        $backup = Write-HostsSafe ([string[]]$new) ([string[]]$clean)
        try { Clear-DnsClientCache } catch { }
        Write-Host "  [OK] Da ghi $($entries.Count) dong vao hosts. Ban sao luu: $backup" -ForegroundColor Green
    } catch {
        Write-Host "  [LOI] Khong ghi duoc hosts (da khoi phuc nguyen trang): $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }

    # 6) Kiem tra dau-cuoi: TLS that toi 127.0.0.1:443 voi tung ten mien
    Write-Host '  Kiem tra dau-cuoi (relay that tren cong 443)...' -ForegroundColor DarkGray
    $badE2E = 0
    foreach ($h in $okHosts) {
        $p = Test-TlsHttp '127.0.0.1' $h 15000 $RelayPort
        if (-not $p.Ok) { $badE2E++; Write-Host ("  [LOI] {0,-38} {1}" -f $h, $p.Msg) -ForegroundColor Red }
    }
    if ($badE2E -eq 0) {
        Write-Host ("  [OK] {0}/{0} ten mien chay tot qua relay (HTTPS)." -f $okHosts.Count) -ForegroundColor Green
    } else {
        Write-Host "  [!] $badE2E ten mien loi khi kiem tra dau-cuoi: xem [10] (log relay)." -ForegroundColor Yellow
    }
    # HTTP thuong (cong 80): Steam lay avatar / mot so file bang http:// (relay tu nang cap len HTTPS neu cong 80 that bai)
    if (Test-RelayListening 80) {
        foreach ($h80n in @('media.steampowered.com', 'avatars.steamstatic.com')) {
            if ($okHosts -contains $h80n) {
                $h80 = Test-HttpPlain $h80n
                if ($h80.Ok) { Write-Host "  [OK] HTTP cong 80 qua relay ($h80n): $($h80.Msg)" -ForegroundColor Green }
                else { Write-Host "  [!] HTTP cong 80 qua relay ($h80n) loi: $($h80.Msg)" -ForegroundColor Yellow }
            }
        }
    } else {
        Write-Host '  [!] Cong 80 khong nghe duoc (co chuong trinh khac chiem?): HTTP thuong toi ten Steam (avatar...) se bi tu choi. Xem [10].' -ForegroundColor Yellow
    }
    return $true
}

function Uninstall-Relay {
    Write-Host "`n--- Go RELAY + khoi hosts cua tool ---" -ForegroundColor Cyan
    Remove-RelayHosts
    Stop-RelayProcesses
    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
        Write-Host "  [OK] Da go tac vu nen '$TaskName'." -ForegroundColor Green
    } catch {
        Write-Host '  (Khong co tac vu nen de go.)' -ForegroundColor DarkGray
    }
    if (Test-Path $DataDir) {
        try { Remove-Item $DataDir -Recurse -Force -ErrorAction Stop; Write-Host '  [OK] Da xoa thu muc du lieu relay.' -ForegroundColor Green }
        catch { Write-Host "  [LOI] Khong xoa duoc ${DataDir}: $($_.Exception.Message)" -ForegroundColor Yellow }
    }
    try { Clear-DnsClientCache } catch { }
    Write-Host '  Mo lai Steam de co hieu luc (chon [5]).' -ForegroundColor Yellow
}

# Lab: thu TUNG kieu chia nho rieng le (chi doc, khong sua he thong) -> biet kieu nao vuot duoc bo loc
function Invoke-FragLab {
    Write-Host "`n--- LAB: thu tung kieu chia nho TLS ClientHello (chi doc, khong sua gi) ---" -ForegroundColor Cyan
    if (-not (Initialize-RelayType)) { return }
    $sample = @('store.fastly.steamstatic.com', 'avatars.fastly.steamstatic.com', 'store.akamai.steamstatic.com',
                'store.steampowered.com', 'steamcommunity.com', 'steamcdn-a.akamaihd.net',
                'cache1-sgp1.steamcontent.com', 'cache1-hkg1.steamcontent.com', 'steampipe.akamaized.net', 'fastly.cdn.steampipe.steamcontent.com')
    $modeNames = @('tcp-early', 'rec-sni', 'tcp-sni', 'plain')
    $tab = @{}
    foreach ($h in $sample) { $tab[$h] = @{} }
    $okCount = @(0, 0, 0, 0)
    for ($m = 0; $m -lt 4; $m++) {
        Write-Host ("  Dang thu kieu [{0}] ..." -f $modeNames[$m]) -ForegroundColor DarkGray
        $res = Invoke-RelayProbe $sample -Mode $m
        if (-not $res) { return }
        foreach ($r in $res) {
            $tab[$r.Host][$m] = $(if ($r.Ok) { 'OK' } else { 'loi' })
            if ($r.Ok) { $okCount[$m]++ }
        }
    }
    Write-Host ''
    Write-Host ('  {0,-44} {1,-10} {2,-9} {3,-9} {4,-6}' -f 'Ten mien', $modeNames[0], $modeNames[1], $modeNames[2], $modeNames[3]) -ForegroundColor White
    foreach ($h in $sample) {
        $cells = @(0..3 | ForEach-Object { $tab[$h][$_] })
        $col = if ($cells[3] -eq 'OK') { 'Green' } elseif ($cells -contains 'OK') { 'Yellow' } else { 'Red' }
        Write-Host ('  {0,-44} {1,-10} {2,-9} {3,-9} {4,-6}' -f $h, $cells[0], $cells[1], $cells[2], $cells[3]) -ForegroundColor $col
    }
    $n = $sample.Count
    $fragBest = ($okCount[0], $okCount[1], $okCount[2] | Measure-Object -Maximum).Maximum
    Write-Host ''
    Write-Host '  plain = gui ClientHello nguyen ven (nhu Steam dang lam); cac kieu con lai = chia nho de nha mang khong doc duoc ten mien.' -ForegroundColor DarkGray
    if ($okCount[3] -ge $n) {
        Write-Host '  KET LUAN: gui nguyen ven cung qua het -> hien tai KHONG thay bo loc. (Loi co the chap chon theo gio/dai IP: chay lai khi Steam loi.)' -ForegroundColor Green
    } elseif ($fragBest -gt $okCount[3]) {
        Write-Host '  KET LUAN: chia nho ClientHello vuot duoc bo loc ma gui nguyen ven thi khong => chon [1] de cai relay se sua duoc.' -ForegroundColor Green
    } else {
        Write-Host '  KET LUAN: khong kieu chia nho nao tot hon gui nguyen ven => bo loc khong bi chia nho danh lua (hoac chan theo IP).' -ForegroundColor Yellow
        Write-Host '            Cach con lai: tunnel (Cloudflare WARP / VPN) khi dung Steam. Doi chung nhanh bang hotspot 4G.' -ForegroundColor Yellow
    }
}

function Show-RelayLog {
    Write-Host "`n--- Log relay (40 dong cuoi) ---" -ForegroundColor Cyan
    $any = $false
    foreach ($lf in @('relay-error.log', 'relay.log')) {
        $p = Join-Path $DataDir $lf
        if (Test-Path $p) {
            $any = $true
            Write-Host "  [$lf]" -ForegroundColor DarkGray
            Get-Content $p -Tail 40 | ForEach-Object { Write-Host "    $_" }
        }
    }
    if (-not $any) { Write-Host '  Chua co log (relay chua duoc cai / chua chay).' -ForegroundColor Yellow }
    Write-Host '  Meo: dong "stat <ten mien> ok=.. fail=.." cho biet Steam co dang dung relay khong (vd. avatars.* khi vao tran CS2).' -ForegroundColor DarkGray
}

# ------------------------------------------------------------
#  DNS + DNS ma hoa (DoH)
# ------------------------------------------------------------
function Set-SteamDns($preset) {
    Write-Host "`n--- Doi DNS sang $($preset.Name) ---" -ForegroundColor Cyan
    foreach ($a in Get-TargetAdapters) {
        $servers = @($preset.V4)
        $v6 = Get-NetAdapterBinding -Name $a.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
        if ($v6.Enabled) { $servers += $preset.V6 }
        try {
            Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $servers -ErrorAction Stop
            Write-Host "  [OK]  $($a.Name): $($servers -join ', ')" -ForegroundColor Green
        } catch {
            Write-Host "  [LOI] $($a.Name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

function Enable-Doh {
    Write-Host "`n--- Bat DNS ma hoa (DoH) de nha mang khong gia mach duoc DNS ---" -ForegroundColor Cyan
    if (-not (Get-Command Add-DnsClientDohServerAddress -ErrorAction SilentlyContinue)) {
        Write-Host '  [BO QUA] Windows nay khong ho tro DoH he thong (can Windows 11).' -ForegroundColor Yellow
        return
    }
    foreach ($ip in $DohTemplates.Keys) {
        try {
            $exists = Get-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue
            if ($exists) {
                Set-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $DohTemplates[$ip] -AllowFallbackToUdp $true -AutoUpgrade $true -ErrorAction Stop
            } else {
                Add-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $DohTemplates[$ip] -AllowFallbackToUdp $true -AutoUpgrade $true -ErrorAction Stop
            }
            Write-Host "  [OK]  $ip" -ForegroundColor Green
        } catch {
            Write-Host "  [LOI] ${ip}: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    try { Clear-DnsClientCache } catch { }
}

function Reset-SteamDns {
    Write-Host "`n--- Khoi phuc DNS tu dong (theo router) ---" -ForegroundColor Cyan
    foreach ($a in Get-TargetAdapters) {
        try {
            Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses -ErrorAction Stop
            Write-Host "  [OK]  $($a.Name)" -ForegroundColor Green
        } catch {
            Write-Host "  [LOI] $($a.Name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host '  (Neu da ghim hosts, chon [4] de go.)' -ForegroundColor DarkGray
}

# ------------------------------------------------------------
#  Cache Steam + khoi dong lai Steam
# ------------------------------------------------------------
function Clear-SteamCache($dir) {
    Write-Host "`n--- Don cache Steam (web, HTTP, avatar) ---" -ForegroundColor Cyan
    if (-not $dir -or -not (Test-Path $dir)) {
        Write-Host '  Khong tim thay thu muc Steam.' -ForegroundColor Yellow
        return
    }
    foreach ($t in @('appcache\httpcache', 'config\htmlcache', 'config\avatarcache')) {
        $p = Join-Path $dir $t
        if (Test-Path $p) {
            try {
                Remove-Item $p -Recurse -Force -ErrorAction Stop
                Write-Host "  [OK]  Da xoa $t" -ForegroundColor Green
            } catch {
                Write-Host "  [LOI] $t : $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "  [-]   $t (chua co)" -ForegroundColor DarkGray
        }
    }
    Write-Host '  Steam se tu tai lai avatar va giao dien khi mo lai.' -ForegroundColor DarkGray
}

function Restart-Steam {
    $steamDir = Get-SteamDir
    $proc = Get-Process steam -ErrorAction SilentlyContinue | Select-Object -First 1
    $steamExe = $null

    if ($proc) {
        $steamExe = $proc.Path
        $ans = Read-Host "`nSteam dang chay. Can tat Steam de don cache va nhan cau hinh mang moi. Tat va mo lai ngay? (Y/N)"
        if ($ans -notmatch '^[yYcC]' -or -not $steamExe) {
            Write-Host '  Nho thoat han Steam (chuot phai icon Steam o khay he thong > Exit), chay lai muc [5] de don cache, roi mo Steam.' -ForegroundColor Yellow
            return
        }
        Write-Host '  Dang tat Steam...'
        Start-Process $steamExe -ArgumentList '-shutdown'
        $deadline = (Get-Date).AddSeconds(30)
        while ((Get-Process steam -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
        Get-Process steam, steamwebhelper -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    Clear-SteamCache $steamDir

    if ($steamExe) {
        # Mo qua explorer de Steam chay bang quyen user thuong, khong phai Admin
        Write-Host '  Dang mo lai Steam...'
        Start-Process explorer.exe -ArgumentList "`"$steamExe`""
        Write-Host '  [OK] Da khoi dong lai Steam.' -ForegroundColor Green
    } else {
        Write-Host "`n  Bay gio ban co the mo Steam." -ForegroundColor Cyan
    }
}

# ------------------------------------------------------------
#  Chan QUIC (UDP 443) cho trinh duyet nhung cua Steam
# ------------------------------------------------------------
function Set-QuicBlock([bool]$on) {
    Write-Host "`n--- $(if ($on) { 'Chan' } else { 'Bo chan' }) QUIC cho steamwebhelper ---" -ForegroundColor Cyan
    try {
        Get-NetFirewallRule -DisplayName $QuicRule -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
        if (-not $on) {
            Write-Host '  [OK] Da bo quy tac chan QUIC.' -ForegroundColor Green
            return
        }
        $dir = Get-SteamDir
        if (-not $dir) { Write-Host '  [LOI] Khong tim thay thu muc Steam.' -ForegroundColor Red; return }
        $exes = @(Get-ChildItem (Join-Path $dir 'bin') -Recurse -Filter steamwebhelper.exe -ErrorAction SilentlyContinue)
        if ($exes.Count -eq 0) { Write-Host '  [LOI] Khong tim thay steamwebhelper.exe.' -ForegroundColor Red; return }
        foreach ($e in $exes) {
            New-NetFirewallRule -DisplayName $QuicRule -Direction Outbound -Action Block -Protocol UDP -RemotePort 443 -Program $e.FullName | Out-Null
            Write-Host "  [OK] $($e.FullName)" -ForegroundColor Green
        }
        Write-Host '  Trinh duyet Steam se tu chuyen sang TCP. Khoi dong lai Steam de co hieu luc.' -ForegroundColor Yellow
    } catch {
        Write-Host "  [LOI] $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ------------------------------------------------------------
#  Chan doan TAI GAME: Steam tai game qua HTTPS (cong 443) toi cache "cacheN-hkg1/sgp1.steamcontent.com",
#  steampipe.akamaized.net, ...  Muc nay doc content_log + thu bat tay TLS that toi tung may chu tai (chi doc).
# ------------------------------------------------------------
function Invoke-DownloadDiag {
    Write-Host "`n--- Chan doan TAI GAME (chi doc, khong sua gi) ---" -ForegroundColor Cyan
    $steam = Get-SteamDir
    if (-not $steam -or -not (Test-Path $steam)) {
        Write-Host '  [LOI] Khong tim thay thu muc Steam.' -ForegroundColor Red
        return
    }
    $log = Join-Path $steam 'logs\content_log.txt'
    if (-not (Test-Path $log)) {
        Write-Host "  Chua co $log (Steam chua tung tai gi?). Bam tai 1 game roi chay lai muc nay." -ForegroundColor Yellow
        return
    }
    $tail = @(Get-Content $log -Tail 600 -ErrorAction SilentlyContinue)

    # 1) Dong loi gan nhat trong log tai game
    $errLines = @($tail | Where-Object { $_ -match '(?i)no connection|error|fail|timed out|timeout|unable|refused|offline|no internet|no cdn|no server' } | Select-Object -Last 10)
    Write-Host '  [content_log.txt] cac dong loi/canh bao gan nhat:' -ForegroundColor White
    if ($errLines.Count -eq 0) { Write-Host '    (khong co dong loi ro rang trong 600 dong cuoi)' -ForegroundColor DarkGray }
    foreach ($l in $errLines) {
        $t = if ($l.Length -gt 170) { $l.Substring(0, 170) + '...' } else { $l }
        Write-Host "    $t" -ForegroundColor DarkYellow
    }

    # 2) May chu tai Steam da thu (dang "HTTPS (SteamCache,525) - ten (ip:443 / ..." hoac "to host ten")
    $txt = $tail -join "`n"
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($txt, '\) - ([a-zA-Z0-9.-]+) \(\d+\.\d+\.\d+\.\d+:\d+')) {
        $v = $m.Groups[1].Value.ToLower()
        if (-not $names.Contains($v)) { $names.Add($v) }
    }
    foreach ($m in [regex]::Matches($txt, '(?i)to host ([a-z0-9.-]+)')) {
        $v = $m.Groups[1].Value.ToLower()
        if ($v -notmatch '^\d+\.\d+\.\d+\.\d+$' -and -not $names.Contains($v)) { $names.Add($v) }
    }
    $names = @($names | Select-Object -First 10)
    Write-Host ''
    if ($names.Count -eq 0) {
        Write-Host '  Log khong ghi ten may chu tai nao gan day -> Steam co the chua lay duoc DANH SACH may chu tai (loi truoc buoc nay).' -ForegroundColor Yellow
    } else {
        Write-Host "  Thu $($names.Count) may chu tai trong log (DNS -> TCP 443 -> bat tay TLS -> HTTP):" -ForegroundColor White
        $okN = 0; $badN = 0; $dnsN = 0; $rstN = 0
        foreach ($n in $names) {
            $ips = @()
            try { $ips = @([System.Net.Dns]::GetHostAddresses($n) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | ForEach-Object { [string]$_ }) } catch { }
            if ($ips.Count -eq 0) { $badN++; $dnsN++; Write-Host ("  [LOI DNS] {0,-44} khong phan giai duoc" -f $n) -ForegroundColor Red; continue }
            $r = Test-TlsHttp $ips[0] $n 4000
            if ($r.Ok) {
                $okN++
                Write-Host ("  [OK]      {0,-44} -> {1} ({2})" -f $n, $ips[0], $r.Msg) -ForegroundColor Green
            } else {
                $badN++
                if ($r.Stage -eq 'tls') { $rstN++ }
                Write-Host ("  [LOI]     {0,-44} -> {1}" -f $n, $ips[0]) -ForegroundColor Red
                Write-Host ("            {0}" -f $r.Msg) -ForegroundColor DarkYellow
            }
        }
        Write-Host ''
        if ($okN -eq 0 -and $badN -gt 0 -and $dnsN -eq $badN) {
            Write-Host '  => Khong phan giai duoc ten may chu tai (loi DNS) -> chon [6] dat DNS Google+Cloudflare roi thu lai.' -ForegroundColor Yellow
        } elseif ($rstN -gt 0) {
            Write-Host '  => TCP toi duoc nhung bat tay TLS bi RESET: CUNG KIEU LOC SNI nhu web Steam, nay ap len ca may chu tai game.' -ForegroundColor Yellow
            Write-Host '     Chon [3] (lab) de xem kieu chia nho nao qua duoc, roi [1]: relay se tu dong dua ca may chu tai (cacheN-hkg1/sgp1, steampipe...) qua duong chia nho.' -ForegroundColor Yellow
        } elseif ($badN -gt 0) {
            Write-Host '  => Mot so may chu tai khong toi duoc (xem ly do o tren). Doi Download Region (Steam > Settings > Downloads) cung co the giup.' -ForegroundColor Yellow
        } else {
            Write-Host '  => May chu tai toi duoc binh thuong tu may nay: loi nam o buoc khac (xem cac dong loi o tren / gui minh doan log).' -ForegroundColor Green
        }
    }

    # 3) Cac thu khac co the lam Steam bao "no internet" khi tai
    Write-Host ''
    if (Test-Path (Join-Path $steam 'steam_dev.cfg')) {
        Write-Host '  [!] Co file steam_dev.cfg trong thu muc Steam (co the ep Steam dung may chu tai/proxy khac). Thu doi ten file roi mo lai Steam.' -ForegroundColor Yellow
    }
    try {
        $blk = @(Get-NetFirewallRule -Direction Outbound -Action Block -Enabled True -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -notlike 'SteamFix*' } |
                 Where-Object { ($_ | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue).Program -like '*steam*' })
        foreach ($b in $blk) { Write-Host "  [!] Quy tac tuong lua dang CHAN chieu ra cua Steam: '$($b.DisplayName)'" -ForegroundColor Yellow }
    } catch { }
}

# ------------------------------------------------------------
#  Chan doan AVATAR (chi doc): relay co thay Steam lay avatar khong? avatarcache co file khong? tai thu 1 avatar that qua relay
# ------------------------------------------------------------
function Get-HttpFetch([string]$url) {
    $hd = New-Object System.Net.Http.HttpClientHandler
    $hd.AllowAutoRedirect = $true
    $c = New-Object System.Net.Http.HttpClient($hd)
    $c.Timeout = [TimeSpan]::FromSeconds(15)
    $c.DefaultRequestHeaders.UserAgent.ParseAdd('Valve/Steam HTTP Client 1.0')
    try {
        $r = $c.GetAsync($url).GetAwaiter().GetResult()
        $bytes = $r.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        $code = [int]$r.StatusCode
        $r.Dispose()
        return @{ Ok = ($code -eq 200); Msg = "HTTP $code, $($bytes.Length) bytes"; Text = [Text.Encoding]::UTF8.GetString($bytes) }
    } catch {
        return @{ Ok = $false; Msg = $_.Exception.GetBaseException().Message; Text = '' }
    } finally {
        $c.Dispose()
    }
}

function Invoke-AvatarDiag {
    Write-Host "`n--- Chan doan AVATAR (chi doc, khong sua gi) ---" -ForegroundColor Cyan
    $steam = Get-SteamDir
    if (-not $steam -or -not (Test-Path $steam)) { Write-Host '  [LOI] Khong tim thay thu muc Steam.' -ForegroundColor Red; return }

    # 1) Relay co thay Steam lay avatar / cdn khong?
    Write-Host '  [1] Relay: cac ten mien avatar/cdn Steam da goi toi relay:' -ForegroundColor White
    $rl = Join-Path $DataDir 'relay.log'
    if (-not (Test-Path $rl)) {
        Write-Host '      (chua co relay.log - relay chua cai/chua chay)' -ForegroundColor Yellow
    } else {
        $last = [ordered]@{}
        foreach ($l in @(Get-Content $rl -Tail 1500 -ErrorAction SilentlyContinue)) {
            if ($l -match 'stat (\S+) ok=(\d+) fail=(\d+) mode=(\S*)') { $last[$Matches[1]] = "ok=$($Matches[2]) fail=$($Matches[3]) mode=$($Matches[4])" }
        }
        $av = @($last.Keys | Where-Object { $_ -match 'avatar|steamcdn|steamuserimages|cdn\.|community|shared|clan' })
        if ($av.Count -eq 0) {
            Write-Host '      KHONG co ket noi avatar/cdn nao di qua relay -> tien trinh Steam lay avatar KHONG dung hosts/relay.' -ForegroundColor Red
        } else {
            $real = 0
            foreach ($k in $av) {
                Write-Host ("      {0,-42} {1}" -f $k, $last[$k]) -ForegroundColor Green
                if ($last[$k] -match 'ok=(\d+)') { if ([int]$Matches[1] -gt 1) { $real++ } }
            }
            if ($real -eq 0) {
                Write-Host '      => tat ca chi ok=1: day chi la 1 lan kiem tra luc cai cua tool, CHUA co ket noi that nao cua Steam/CS2 toi cac ten mien nay qua relay.' -ForegroundColor Yellow
            }
        }
        $http = @(Get-Content $rl -Tail 1500 -ErrorAction SilentlyContinue | Where-Object { $_ -match 'http (fail|reject)' } | Select-Object -Last 5)
        foreach ($h in $http) { Write-Host "      $h" -ForegroundColor DarkYellow }
    }

    # 2) avatarcache cua Steam
    Write-Host '  [2] Thu muc Steam\config\avatarcache:' -ForegroundColor White
    $ac = Join-Path $steam 'config\avatarcache'
    if (-not (Test-Path $ac)) {
        Write-Host '      (khong ton tai: Steam chua luu avatar nao)' -ForegroundColor Yellow
    } else {
        $files = @(Get-ChildItem $ac -File -ErrorAction SilentlyContinue)
        $zero = @($files | Where-Object { $_.Length -eq 0 }).Count
        $new = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        Write-Host ("      {0} file ({1} file rong); moi nhat: {2}" -f $files.Count, $zero, $(if ($new) { $new.LastWriteTime } else { '-' })) -ForegroundColor $(if ($files.Count -gt 0) { 'Green' } else { 'Yellow' })
    }

    # 3) Tai thu 1 avatar that (cua ban) qua he thong (hosts -> relay)
    Write-Host '  [3] Tai thu avatar that qua he thong (hosts -> relay):' -ForegroundColor White
    $id = $null
    $lu = Join-Path $steam 'config\loginusers.vdf'
    if (Test-Path $lu) {
        $t = Get-Content $lu -Raw -ErrorAction SilentlyContinue
        $mm = [regex]::Match($t, '(?s)"(\d{17})"\s*\{[^{}]*?"MostRecent"\s+"1"')
        if ($mm.Success) { $id = $mm.Groups[1].Value }
    }
    $paths = New-Object System.Collections.Generic.List[string]
    if ($id) {
        $x = Get-HttpFetch "https://steamcommunity.com/profiles/$id/?xml=1"
        if ($x.Ok -and $x.Text -match '<avatarFull><!\[CDATA\[https?://[^/]+(/[^\]]+)\]\]></avatarFull>') { $paths.Add($Matches[1]) }
        else { Write-Host "      Khong lay duoc profile XML ($($x.Msg)); dung avatar mac dinh cua Steam de thu." -ForegroundColor DarkYellow }
    }
    $paths.Add('/fef49e7fa7e1997310d705b2a6158ff8dc1cdfeb_full.jpg')
    $mapped = @(Get-RelayMapped)
    foreach ($ap in @($paths | Select-Object -First 2)) {
        foreach ($hn in @('avatars.fastly.steamstatic.com', 'avatars.akamai.steamstatic.com', 'avatars.cloudflare.steamstatic.com', 'avatars.steamstatic.com', 'steamcdn-a.akamaihd.net')) {
            $u = if ($hn -eq 'steamcdn-a.akamaihd.net') { "https://$hn/steamcommunity/public/images/avatars" + ($ap -replace '^/(..)(.*)$', '/$1/$1$2') } else { "https://$hn$ap" }
            $r = Get-HttpFetch $u
            $tag = if ($mapped -contains $hn) { '[relay]' } else { '[truc tiep]' }
            Write-Host ("      {0,-38} {1,-11} {2}" -f $hn, $tag, $r.Msg) -ForegroundColor $(if ($r.Ok) { 'Green' } else { 'Red' })
        }
        break
    }

    # 4) Log cua Steam nhac toi avatar
    Write-Host '  [4] Log Steam nhac toi "avatar" (cuoi):' -ForegroundColor White
    $found = 0
    foreach ($f in @(Get-ChildItem (Join-Path $steam 'logs') -Filter '*.txt' -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'content_log.txt' })) {
        $hit = @(Get-Content $f.FullName -Tail 3000 -ErrorAction SilentlyContinue | Where-Object { $_ -match '(?i)avatar' } | Select-Object -Last 4)
        foreach ($h in $hit) {
            $found++
            $tt = if ($h.Length -gt 160) { $h.Substring(0, 160) + '...' } else { $h }
            Write-Host ("      [{0}] {1}" -f $f.Name, $tt) -ForegroundColor DarkYellow
        }
    }
    if ($found -eq 0) { Write-Host '      (khong co dong nao)' -ForegroundColor DarkGray }
    # 5) Ket noi dang mo cua Steam / CS2: co di vao relay (127.0.0.1) khong, hay di thang ra ngoai?
    Write-Host '  [5] Ket noi TCP dang mo cua steam / steamwebhelper / cs2 (cong 80, 443):' -ForegroundColor White
    $anyProc = $false
    foreach ($pn in @('steam', 'steamwebhelper', 'cs2')) {
        $pids = @(Get-Process -Name $pn -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
        if ($pids.Count -eq 0) { continue }
        $anyProc = $true
        $cn = @()
        foreach ($pp in $pids) { $cn += @(Get-NetTCPConnection -OwningProcess $pp -State Established -ErrorAction SilentlyContinue | Where-Object { $_.RemotePort -in @(80, 443) }) }
        $toRelay = @($cn | Where-Object { $_.RemoteAddress -eq '127.0.0.1' }).Count
        $direct  = @($cn | Where-Object { $_.RemoteAddress -ne '127.0.0.1' })
        Write-Host ("      {0,-15} qua relay: {1,-3} | thang ra ngoai: {2}" -f $pn, $toRelay, $direct.Count)
        foreach ($g in @($direct | Group-Object { "$($_.RemoteAddress):$($_.RemotePort)" } | Sort-Object Count -Descending | Select-Object -First 4)) {
            Write-Host ("          -> {0,-28} x{1}" -f $g.Name, $g.Count) -ForegroundColor DarkGray
        }
    }
    if (-not $anyProc) { Write-Host '      (Steam/CS2 dang khong chay - mo game roi chay lai muc nay)' -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host '  Doc ket qua: [1] trong = Steam lay avatar bang duong khac (khong qua hosts); [3] tai duoc ma [1]/[2] van trong = loi o phia Steam/CS2, khong phai mang.' -ForegroundColor DarkGray
}

# ------------------------------------------------------------
#  Sua toan dien
# ------------------------------------------------------------
function Invoke-FullFix {
    Set-SteamDns $DnsPreset
    Enable-Doh
    Show-DnsStatus
    $ok = Install-Relay
    if ($ok) {
        $null = Test-SteamConnection
    } else {
        Write-Host "`nRelay chua duoc cai -> cac loi CSS/avatar do loc SNI se chua het. Xem thong bao o tren, hoac chay [3] (lab)." -ForegroundColor Yellow
    }
    Restart-Steam
}

function Show-Menu {
    Write-Host ''
    Write-Host '==================== MENU ====================' -ForegroundColor Cyan
    Write-Host '  [1] SUA TOAN DIEN (khuyen dung): DNS Google+Cloudflare + DNS ma hoa, thu & cai RELAY vuot loc SNI'
    Write-Host '      (web + avatar + may chu TAI GAME; tac vu nen + hosts, hoi truoc khi ghi), don cache, mo lai Steam'
    Write-Host '  [2] Quet lai + trang thai relay (chi doc, khong sua gi)'
    Write-Host '  [3] LAB: thu tung kieu chia nho TLS xem kieu nao vuot duoc nha mang (chi doc)'
    Write-Host '  [4] Go RELAY + khoi hosts cua tool (dong hosts cua ban giu nguyen)'
    Write-Host '  [5] Don cache Steam (web + avatar) va mo lai Steam'
    Write-Host '  [6] Chi dat DNS Google+Cloudflare + DNS ma hoa'
    Write-Host '  [7] Khoi phuc DNS tu dong nhu ban dau'
    Write-Host '  [8] Chan QUIC cho trinh duyet Steam (chi khi web Steam load CHAM)'
    Write-Host '  [9] Bo chan QUIC'
    Write-Host ' [10] Xem log relay'
    Write-Host ' [11] Chan doan: bi chan theo IP hay theo TEN MIEN/SNI (chi doc)'
    Write-Host ' [12] Chan doan TAI GAME: doc content_log + thu may chu tai (chi doc)'
    Write-Host ' [13] Chan doan AVATAR: relay/avatarcache/tai thu avatar that (chi doc)'
    Write-Host '  [0] Thoat'
    Read-Host 'Chon'
}

try {
    Clear-Host
    Write-Host "=== SUA LOI STEAM $Ver : -105 / MAT GIAO DIEN / AVATAR MAC DINH / MADE BY V - TRAN HIEU NGHIA ===" -ForegroundColor Cyan
    Show-DnsStatus
    Show-RelayStatus
    $null = Repair-DamagedHosts
    $null = Test-SteamConnection
    Repair-HostsFile

    :menu while ($true) {
        switch ((Show-Menu).Trim()) {
            '1'  { Invoke-FullFix }
            '2'  { Show-DnsStatus; Show-RelayStatus; $null = Test-SteamConnection }
            '3'  { Invoke-FragLab }
            '4'  { Uninstall-Relay; $null = Test-SteamConnection }
            '5'  { Restart-Steam }
            '6'  { Set-SteamDns $DnsPreset; Enable-Doh; Show-DnsStatus }
            '7'  { Reset-SteamDns; Show-DnsStatus; $null = Test-SteamConnection }
            '8'  { Set-QuicBlock $true }
            '9'  { Set-QuicBlock $false }
            '10' { Show-RelayLog }
            '11' { Invoke-SniDiagnosis }
            '12' { Invoke-DownloadDiag }
            '13' { Invoke-AvatarDiag }
            '0'  { break menu }
            default { Write-Host 'Lua chon khong hop le.' -ForegroundColor Yellow }
        }
    }
} catch {
    Write-Host "`n[LOI] $($_.Exception.Message)" -ForegroundColor Red
    Read-Host 'Nhan Enter de thoat'
}
