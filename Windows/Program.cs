using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Web.Script.Serialization;
using Microsoft.Win32;
using Microsoft.Web.WebView2.Core;

namespace GroundSurf {
    internal static class AppLog {
        internal static readonly string Folder=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"GroundSurf");
        internal static void Write(string operation,Exception error) {
            try {
                Directory.CreateDirectory(Folder);var file=Path.Combine(Folder,"errors.log");
                if(File.Exists(file) && new FileInfo(file).Length>256*1024)File.Delete(file);
                File.AppendAllText(file,DateTime.UtcNow.ToString("o")+" "+operation+": "+error.Message+Environment.NewLine);
            } catch { }
        }
    }
    public sealed class Preferences {
        public bool Paused {get;set;}
        public int Speed {get;set;}=12;
        public string Appearance {get;set;}="light";
        public bool PauseFullscreen {get;set;}=true;
        public bool PauseBattery {get;set;}
        internal static Preferences Load() {
            try {
                var value=new JavaScriptSerializer().Deserialize<Preferences>(File.ReadAllText(Path.Combine(AppLog.Folder,"settings.json")));
                if(value==null)return new Preferences();
                if(value.Appearance!="light" && value.Appearance!="dark" && value.Appearance!="purple" && value.Appearance!="system")value.Appearance="light";
                if(value.Speed!=6 && value.Speed!=12 && value.Speed!=24)value.Speed=12;
                return value;
            } catch{return new Preferences();}
        }
        internal void Save() {
            try {Directory.CreateDirectory(AppLog.Folder);File.WriteAllText(Path.Combine(AppLog.Folder,"settings.json"),new JavaScriptSerializer().Serialize(this));}
            catch(Exception e){AppLog.Write("Save settings",e);}
        }
    }
    internal sealed class MessageSink : Form {
        internal event Action DesktopChanged;
        internal event Action<bool> DisplaySleeping;
        internal event Action<bool> ComputerSleeping;
        readonly uint taskbar=NativeDesktop.RegisterWindowMessage("TaskbarCreated");
        IntPtr power;
        internal MessageSink() {
            ShowInTaskbar=false;FormBorderStyle=FormBorderStyle.None;
            var handle=Handle;var guid=new Guid("6fe69556-704a-47a0-8f24-c28d936fda47");
            power=NativeDesktop.RegisterPowerSettingNotification(handle,ref guid,0);
        }
        protected override void WndProc(ref Message m) {
            if((uint)m.Msg==taskbar)DesktopChanged?.Invoke();
            if(m.Msg==0x218) {
                if(m.WParam.ToInt32()==4)ComputerSleeping?.Invoke(true);
                if(m.WParam.ToInt32()==7 || m.WParam.ToInt32()==18)ComputerSleeping?.Invoke(false);
                if(m.WParam.ToInt32()==0x8013 && m.LParam!=IntPtr.Zero) {
                    var id=(Guid)System.Runtime.InteropServices.Marshal.PtrToStructure(m.LParam,typeof(Guid));
                    if(id==new Guid("6fe69556-704a-47a0-8f24-c28d936fda47") && System.Runtime.InteropServices.Marshal.ReadInt32(m.LParam,16)>=4)
                        DisplaySleeping?.Invoke(System.Runtime.InteropServices.Marshal.ReadInt32(m.LParam,20)==0);
                }
            }
            base.WndProc(ref m);
        }
        protected override void Dispose(bool disposing) {if(power!=IntPtr.Zero){NativeDesktop.UnregisterPowerSettingNotification(power);power=IntPtr.Zero;}base.Dispose(disposing);}
    }
    internal sealed class GroundSurfContext : ApplicationContext {
        readonly Preferences settings;
        readonly MessageSink sink=new MessageSink();
        readonly NotifyIcon tray;
        readonly Icon icon;
        readonly List<WallpaperWindow> views=new List<WallpaperWindow>();
        readonly System.Windows.Forms.Timer ticks=new System.Windows.Forms.Timer {Interval=33};
        readonly System.Windows.Forms.Timer checks=new System.Windows.Forms.Timer {Interval=1000};
        readonly ToolStripMenuItem pauseItem;
        readonly string testReport;
        CoreWebView2Environment environment;
        DesktopTarget target;
        bool locked, displaySleeping, computerSleeping, rebuilding, disposed;
        string layout="";
        DateTime retryAfter=DateTime.MinValue;
        internal GroundSurfContext(string report=null) {
            testReport=report;settings=report==null ? Preferences.Load() : new Preferences {PauseFullscreen=false};
            icon=Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            var menu=new ContextMenuStrip();menu.Items.Add("GroundSurf").Enabled=false;
            pauseItem=new ToolStripMenuItem("Pause",null,(_,__)=>{settings.Paused=!settings.Paused;settings.Save();RefreshPlayback();});menu.Items.Add(pauseItem);
            var speeds=new ToolStripMenuItem("Scroll speed");
            foreach(var item in new[]{Tuple.Create("Slow",6),Tuple.Create("Gentle",12),Tuple.Create("Brisk",24)}) {
                var entry=new ToolStripMenuItem(item.Item1) {Tag=item.Item2};
                entry.Click+=(_,__)=>{settings.Speed=(int)entry.Tag;settings.Save();RefreshPlayback();};speeds.DropDownItems.Add(entry);
            }
            speeds.DropDownOpening+=(_,__)=>{foreach(ToolStripMenuItem item in speeds.DropDownItems)item.Checked=(int)item.Tag==settings.Speed;};menu.Items.Add(speeds);
            menu.Items.Add("New landscape",null,(_,__)=>{foreach(var view in views)view.NewLandscape();});
            var appearances=new ToolStripMenuItem("Appearance");
            foreach(var option in new[]{Tuple.Create("Light","light"),Tuple.Create("Dark","dark"),Tuple.Create("Dark Purple","purple"),Tuple.Create("Follow system","system")}) {
                var entry=new ToolStripMenuItem(option.Item1) {Tag=option.Item2};
                entry.Click+=(_,__)=>{settings.Appearance=(string)entry.Tag;settings.Save();RefreshPlayback();};
                appearances.DropDownItems.Add(entry);
            }
            appearances.DropDownOpening+=(_,__)=>{foreach(ToolStripMenuItem entry in appearances.DropDownItems)entry.Checked=(string)entry.Tag==settings.Appearance;};menu.Items.Add(appearances);
            var full=new ToolStripMenuItem("Pause for fullscreen apps") {Checked=settings.PauseFullscreen,CheckOnClick=true};
            full.Click+=(_,__)=>{settings.PauseFullscreen=full.Checked;settings.Save();RefreshPlayback();};menu.Items.Add(full);
            var battery=new ToolStripMenuItem("Pause on battery") {Checked=settings.PauseBattery,CheckOnClick=true};
            battery.Click+=(_,__)=>{settings.PauseBattery=battery.Checked;settings.Save();RefreshPlayback();};menu.Items.Add(battery);
            var startup=new ToolStripMenuItem("Start with Windows") {CheckOnClick=true};
            menu.Opening+=(_,__)=>startup.Checked=StartupEnabled();
            startup.Click+=(_,__)=>SetStartup(startup.Checked);menu.Items.Add(startup);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("About GroundSurf",null,(_,__)=>MessageBox.Show("GroundSurf by Akhilesh Khajuria\nWindows preview 0.1.0\n\nOriginal artwork generator: Lingdong Huang (MIT).\nOffline, endlessly generated landscapes.","About GroundSurf",MessageBoxButtons.OK,MessageBoxIcon.Information));
            menu.Items.Add("Quit",null,(_,__)=>ExitThread());
            tray=new NotifyIcon {Icon=icon,Text="GroundSurf",ContextMenuStrip=menu,Visible=report==null};
            ticks.Tick+=(_,__)=>{foreach(var view in views)view.Tick();};
            checks.Tick+=async (_,__)=>{
                if(!rebuilding && DateTime.UtcNow>=retryAfter && (target!=null && !target.Valid || views.Any(v=>v.IsDisposed || target!=null && !v.Attached))) {
                    try {await Rebuild();}catch(Exception e){AppLog.Write("Desktop retry",e);}
                }
                RefreshPlayback();
            };
            sink.DesktopChanged+=()=>{tray.Visible=false;tray.Visible=testReport==null;QueueRebuild();};
            sink.DisplaySleeping+=value=>{displaySleeping=value;RefreshPlayback();};
            sink.ComputerSleeping+=value=>{computerSleeping=value;RefreshPlayback();};
            SystemEvents.DisplaySettingsChanged+=DisplaysChanged;
            SystemEvents.SessionSwitch+=SessionChanged;
            SystemEvents.SessionEnding+=SessionEnding;
            _=Start();
        }
        async Task Start() {
            try {
                await CreateEnvironment();await Rebuild();checks.Start();
                if(testReport!=null)await SmokeTest();
            }catch(Exception e){AppLog.Write("Startup",e);if(testReport!=null)WriteTestFailure(e);else MessageBox.Show(e.Message,"GroundSurf could not start",MessageBoxButtons.OK,MessageBoxIcon.Error);ExitThread();}
        }
        async Task CreateEnvironment() {
            // One environment is shared across displays; use the installed Evergreen
            // engine rather than packaging another complete Chromium distribution.
            var options=new CoreWebView2EnvironmentOptions("--disable-features=CalculateNativeWinOcclusion --disk-cache-size=1048576 --media-cache-size=1048576");
            environment=await CoreWebView2Environment.CreateAsync(null,Path.Combine(AppLog.Folder,"WebView2"),options);
        }
        async Task Rebuild() {
            if(rebuilding || disposed)return;rebuilding=true;ticks.Stop();
            try {
                foreach(var view in views.ToArray())view.Dispose();views.Clear();
                var screens=Screen.AllScreens;
                layout=string.Join(";",screens.Select(s=>s.DeviceName+":"+s.Bounds));
                target=testReport==null ? NativeDesktop.Discover() : null;
                foreach(var screen in screens) {
                    var view=new WallpaperWindow(screen.Bounds,target,icon);views.Add(view);
                    view.BrowserExited+=()=>{UI(async ()=>{try {await CreateEnvironment();await Rebuild();}catch(Exception e){AppLog.Write("Browser recovery",e);}});};
                    view.SetPlayback(settings.Paused || locked || displaySleeping || computerSleeping,settings.Speed,settings.Appearance);
                    await view.Initialize(environment,testReport==null ? null : "GroundSurf-quality");
                }
                retryAfter=DateTime.MinValue;
            }catch(Exception e){retryAfter=DateTime.UtcNow.AddSeconds(5);AppLog.Write("Desktop attach",e);throw;}
            finally {rebuilding=false;RefreshPlayback();}
        }
        void RefreshPlayback() {
            if(disposed)return;
            pauseItem.Text=settings.Paused ? "Resume" : "Pause";
            var global=settings.Paused || locked || displaySleeping || computerSleeping || settings.PauseBattery && SystemInformation.PowerStatus.PowerLineStatus==PowerLineStatus.Offline;
            bool active=false;
            foreach(var view in views) {
                if(view.IsDisposed)continue;
                var pause=global || settings.PauseFullscreen && NativeDesktop.CoveredByFullscreen(view.DisplayBounds);
                view.SetPlayback(pause,settings.Speed,settings.Appearance);active|=!pause;
            }
            ticks.Enabled=active && !rebuilding;
        }
        void UI(Action action) {if(!disposed && !sink.IsDisposed)try {sink.BeginInvoke(action);}catch(InvalidOperationException) { }}
        void QueueRebuild(){UI(async ()=>{try {await Rebuild();}catch(Exception e){AppLog.Write("Desktop recovery",e);if(testReport==null)tray.ShowBalloonTip(5000,"GroundSurf",e.Message,ToolTipIcon.Warning);}});}
        void DisplaysChanged(object sender,EventArgs e){UI(()=>{var current=string.Join(";",Screen.AllScreens.Select(s=>s.DeviceName+":"+s.Bounds));if(current!=layout)QueueRebuild();});}
        void SessionChanged(object sender,SessionSwitchEventArgs e){UI(()=>{if(e.Reason==SessionSwitchReason.SessionLock)locked=true;if(e.Reason==SessionSwitchReason.SessionUnlock)locked=false;RefreshPlayback();});}
        void SessionEnding(object sender,SessionEndingEventArgs e){UI(()=>ExitThread());}
        static bool StartupEnabled(){using(var key=Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run"))return key?.GetValue("GroundSurf") is string value && value.Contains(Application.ExecutablePath);}
        static void SetStartup(bool enabled) {
            try {using(var key=Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run")){if(enabled)key.SetValue("GroundSurf","\""+Application.ExecutablePath+"\"");else key.DeleteValue("GroundSurf",false);}}
            catch(Exception e){MessageBox.Show(e.Message,"Could not change startup setting");}
        }
        async Task<Dictionary<string,object>> ReadStats(WallpaperWindow view) {
            var serializer=new JavaScriptSerializer();var encoded=await view.Stats();
            var json=serializer.Deserialize<string>(encoded);return serializer.Deserialize<Dictionary<string,object>>(json);
        }
        async Task SmokeTest() {
            var deadline=DateTime.UtcNow.AddSeconds(45);var view=views[0];Dictionary<string,object> stats=null;
            while(DateTime.UtcNow<deadline) {
                if(view.Loaded){stats=await ReadStats(view);if(stats!=null && stats.ContainsKey("objects") && Convert.ToDouble(stats["position"])>5)break;}
                await Task.Delay(250);
            }
            if(stats==null || !stats.ContainsKey("objects") || Convert.ToDouble(stats["position"])<=5)throw new Exception("Windows renderer did not generate and scroll a scene.");
            if(Convert.ToString(stats["lastError"])!="")throw new Exception("Renderer reported an error.");
            settings.Paused=true;RefreshPlayback();await Task.Delay(300);
            var paused=await ReadStats(view);await Task.Delay(1000);var later=await ReadStats(view);
            if(ticks.Enabled || Convert.ToDouble(paused["position"])!=Convert.ToDouble(later["position"]))throw new Exception("Pause did not stop the animation timer and cursor.");
            foreach(var mode in new[]{"dark","purple","system","light"}) {
                settings.Appearance=mode;RefreshPlayback();await Task.Delay(300);
                var themed=await ReadStats(view);
                if(Convert.ToString(themed["appearance"])!=mode || mode!="system" && Convert.ToBoolean(themed["dark"])!=(mode=="dark" || mode=="purple"))throw new Exception("Appearance did not apply: "+mode);
                if(mode=="purple") {
                    using(var capture=new MemoryStream()) {
                        await view.Snapshot(capture);capture.Position=0;
                        using(var bitmap=new Bitmap(capture)) {
                            var colour=bitmap.GetPixel(5,5);
                            if(!(colour.B>colour.R && colour.R>colour.G))throw new Exception("Purple appearance was not painted in the WebView snapshot.");
                        }
                    }
                }
                if(Convert.ToDouble(themed["position"])!=Convert.ToDouble(later["position"]) || Convert.ToInt32(themed["objects"])!=Convert.ToInt32(later["objects"]))throw new Exception("Appearance changed the landscape or resumed paused playback.");
            }
            locked=true;settings.Paused=false;RefreshPlayback();if(ticks.Enabled)throw new Exception("Session lock did not stop the timer.");
            computerSleeping=true;displaySleeping=true;locked=false;computerSleeping=false;RefreshPlayback();if(ticks.Enabled)throw new Exception("Computer wake overrode display sleep.");
            displaySleeping=false;RefreshPlayback();if(!ticks.Enabled)throw new Exception("Wake did not restart the timer.");
            settings.Speed=24;RefreshPlayback();await Task.Delay(750);
            using(var stream=File.Create(Path.ChangeExtension(testReport,"png")))await view.Snapshot(stream);
            var attachment="not-tested";
            DesktopTarget host=null;
            try {host=NativeDesktop.Discover();}
            catch(Exception e){attachment="desktop-unavailable: "+e.Message;}
            if(host!=null) {
                var test=new WallpaperWindow(new Rectangle(0,0,320,240),host,icon);
                try {
                    await test.Initialize(environment,"GroundSurf-desktop-check");
                    if(!test.Attached)throw new Exception("Parent attachment mismatch");
                    var expires=DateTime.UtcNow.AddSeconds(15);bool rendered=false;
                    while(DateTime.UtcNow<expires) {
                        test.Tick();
                        if(test.Loaded) {
                            var result=await ReadStats(test);
                            if(result!=null && result.ContainsKey("objects") && Convert.ToDouble(result["position"])>3 && Convert.ToString(result["lastError"])==""){rendered=true;break;}
                        }
                        await Task.Delay(100);
                    }
                    if(!rendered)throw new Exception("Attached desktop WebView did not generate and scroll.");
                    attachment="renderer-and-parent-verified";
                } finally {test.Dispose();}
            }
            var report=new {result="PASS",engine=environment.BrowserVersionString,scrolled=true,pauseStoppedTimer=true,appearanceSwitching=true,overlappingSleepStates=true,desktopAttachment=attachment,stats=await ReadStats(view)};
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(testReport)));
            File.WriteAllText(testReport,new JavaScriptSerializer().Serialize(report));ExitThread();
        }
        void WriteTestFailure(Exception e){Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(testReport)));File.WriteAllText(testReport,new JavaScriptSerializer().Serialize(new{result="FAIL",error=e.ToString()}));Environment.ExitCode=1;}
        protected override void ExitThreadCore(){Dispose();base.ExitThreadCore();}
        protected override void Dispose(bool disposing) {
            if(disposed)return;disposed=true;
            ticks.Stop();checks.Stop();SystemEvents.DisplaySettingsChanged-=DisplaysChanged;SystemEvents.SessionSwitch-=SessionChanged;SystemEvents.SessionEnding-=SessionEnding;
            foreach(var view in views)view.Dispose();views.Clear();tray.Visible=false;tray.Dispose();icon.Dispose();sink.Dispose();ticks.Dispose();checks.Dispose();
            base.Dispose(disposing);
        }
    }
    internal static class Program {
        [STAThread] static void Main(string[] args) {
            Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
            string report=args.Length==2 && args[0]=="--smoke-test" ? args[1] : null;
            using(var mutex=new Mutex(true,"Local\\GroundSurf.Windows",out var first)) {
                if(!first)return;
                try {
                    CoreWebView2Environment.GetAvailableBrowserVersionString();
                    Application.Run(new GroundSurfContext(report));
                }catch(WebView2RuntimeNotFoundException) {
                    if(report!=null){File.WriteAllText(report,"{\"result\":\"FAIL\",\"error\":\"WebView2 Runtime missing\"}");Environment.ExitCode=1;}
                    else MessageBox.Show("GroundSurf needs Microsoft Edge WebView2 Runtime.\n\nDownload the Evergreen Runtime from:\nhttps://developer.microsoft.com/microsoft-edge/webview2/","WebView2 Runtime needed",MessageBoxButtons.OK,MessageBoxIcon.Information);
                }catch(Exception e){AppLog.Write("Fatal",e);if(report!=null){File.WriteAllText(report,new JavaScriptSerializer().Serialize(new {result="FAIL",error=e.ToString()}));Environment.ExitCode=1;}else MessageBox.Show(e.Message,"GroundSurf");}
            }
        }
    }
}
