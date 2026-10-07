using System;
using System.Drawing;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace GroundSurf {
    internal sealed class WallpaperWindow : Form {
        internal readonly Rectangle DisplayBounds;
        readonly WebView2 browser;
        readonly DesktopTarget desktop;
        bool ready, ticking, pauseApplied, changingPlayback;
        bool desiredPause;
        int desiredSpeed=12, appliedSpeed=-1;
        string desiredAppearance="light",appliedAppearance=null;
        string source;
        internal bool Attached => desktop!=null && !IsDisposed && NativeDesktop.GetParent(Handle)==desktop.Parent;
        internal bool Loaded => ready;
        internal WallpaperWindow(Rectangle bounds, DesktopTarget target, Icon icon) {
            DisplayBounds=bounds;desktop=target;Icon=icon;
            FormBorderStyle=FormBorderStyle.None;ShowInTaskbar=false;StartPosition=FormStartPosition.Manual;
            AutoScaleMode=AutoScaleMode.None;Bounds=bounds;BackColor=Color.FromArgb(244,236,217);
            browser=new WebView2 {Dock=DockStyle.Fill,DefaultBackgroundColor=BackColor,Enabled=false};Controls.Add(browser);
        }
        protected override bool ShowWithoutActivation=>true;
        protected override CreateParams CreateParams {get {var p=base.CreateParams;p.ExStyle|=0x80|0x08000000|0x20;return p;}}
        protected override void WndProc(ref Message m) {
            if(m.Msg==0x21){m.Result=new IntPtr(3);return;}
            if(m.Msg==0x84){m.Result=new IntPtr(-1);return;}
            base.WndProc(ref m);
        }
        internal async Task Initialize(CoreWebView2Environment environment,string seed=null) {
            if(desktop!=null)NativeDesktop.Attach(Handle,DisplayBounds,desktop);
            Show();
            await browser.EnsureCoreWebView2Async(environment);
            if(IsDisposed)return;
            var core=browser.CoreWebView2;
            core.Settings.AreDefaultContextMenusEnabled=false;core.Settings.AreDevToolsEnabled=false;
            core.Settings.AreBrowserAcceleratorKeysEnabled=false;core.Settings.IsStatusBarEnabled=false;
            core.Settings.IsZoomControlEnabled=false;core.Settings.IsPinchZoomEnabled=false;
            core.SetVirtualHostNameToFolderMapping("groundsurf.local",AppDomain.CurrentDomain.BaseDirectory,CoreWebView2HostResourceAccessKind.DenyCors);
            core.NewWindowRequested+=(_,e)=>e.Handled=true;
            core.PermissionRequested+=(_,e)=>e.State=CoreWebView2PermissionState.Deny;
            core.DownloadStarting+=(_,e)=>e.Cancel=true;
            source="https://groundsurf.local/landscape.html"+(seed==null ? "" : "?seed="+Uri.EscapeDataString(seed));
            core.NavigationStarting+=(_,e)=>{if(!e.Uri.StartsWith("https://groundsurf.local/",StringComparison.OrdinalIgnoreCase))e.Cancel=true;else ready=false;};
            core.NavigationCompleted+=async (_,e)=>{
                if(!e.IsSuccess || IsDisposed)return;
                ready=true;pauseApplied=false;appliedSpeed=-1;appliedAppearance=null;
                await ApplyPlayback();
            };
            core.ProcessFailed+=(_,e)=>{
                if(IsDisposed)return;
                if(e.ProcessFailedKind==CoreWebView2ProcessFailedKind.BrowserProcessExited) {
                    // Recreate the environment/controllers on the application context.
                    ready=false;BrowserExited?.Invoke();
                } else if(e.ProcessFailedKind==CoreWebView2ProcessFailedKind.RenderProcessExited) {
                    ready=false;core.Reload();
                }
            };
            core.Navigate(source);
        }
        internal event Action BrowserExited;
        internal void SetPlayback(bool pause,int speed,string appearance="light") {
            if(pause==desiredPause && speed==desiredSpeed && pause==pauseApplied && speed==appliedSpeed && appearance==desiredAppearance && appearance==appliedAppearance)return;
            desiredPause=pause;desiredSpeed=speed;desiredAppearance=appearance=="dark" || appearance=="purple" || appearance=="system" ? appearance : "light";
            if(ready)_=ApplyPlayback();
        }
        async Task ApplyPlayback() {
            if(changingPlayback || !ready || IsDisposed)return;
            changingPlayback=true;
            try {
                // Serialize pause/resume work; a newer desired state is applied in the loop.
                do {
                    var pause=desiredPause;var speed=desiredSpeed;var appearance=desiredAppearance;
                    await browser.CoreWebView2.ExecuteScriptAsync("window.wallpaper?.appearance('"+appearance+"');window.wallpaper?.speed("+speed+");window.wallpaper?.pause("+(pause?"true":"false")+")");
                    pauseApplied=pause;appliedSpeed=speed;appliedAppearance=appearance;
                    if(pause==desiredPause && speed==desiredSpeed && appearance==desiredAppearance)break;
                } while(ready && !IsDisposed);
            } catch(Exception e) {AppLog.Write("Playback",e);}
            finally {changingPlayback=false;}
        }
        internal async void Tick() {
            if(!ready || desiredPause || ticking || IsDisposed)return;
            ticking=true;
            try {await browser.CoreWebView2.ExecuteScriptAsync("window.wallpaper?.tick()");}
            catch(Exception e){AppLog.Write("Tick",e);}
            finally {ticking=false;}
        }
        internal void NewLandscape(){if(ready)browser.CoreWebView2.Reload();}
        internal Task<string> Stats()=>browser.CoreWebView2.ExecuteScriptAsync("JSON.stringify(window.wallpaper?.stats())");
        internal Task Snapshot(Stream output)=>browser.CoreWebView2.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png,output);
        protected override void Dispose(bool disposing){ready=false;if(disposing)browser.Dispose();base.Dispose(disposing);}
    }
}
