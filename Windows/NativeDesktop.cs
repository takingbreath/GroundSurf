using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;

namespace GroundSurf {
    internal sealed class DesktopTarget {
        public IntPtr Parent, Icons, Underlay;
        public bool Layered;
        public bool Valid => Parent != IntPtr.Zero && NativeDesktop.IsWindow(Parent);
    }
    internal static class NativeDesktop {
        internal delegate bool EnumCallback(IntPtr hwnd, IntPtr data);
        [StructLayout(LayoutKind.Sequential)] internal struct Point { public int X, Y; }
        [StructLayout(LayoutKind.Sequential)] internal struct Rect { public int Left, Top, Right, Bottom; }
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr FindWindow(string cls, string title);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumCallback callback, IntPtr data);
        [DllImport("user32.dll", SetLastError=true)] static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
        [DllImport("user32.dll", SetLastError=true)] static extern IntPtr SetParent(IntPtr child, IntPtr parent);
        [DllImport("user32.dll")] internal static extern IntPtr GetParent(IntPtr hwnd);
        [DllImport("kernel32.dll")] static extern void SetLastError(uint error);
        [DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetStyle(IntPtr hwnd, int index);
        [DllImport("user32.dll", EntryPoint="SetWindowLongPtrW")] static extern IntPtr SetStyle(IntPtr hwnd, int index, IntPtr style);
        [DllImport("user32.dll", SetLastError=true)] static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint color, byte alpha, uint flags);
        [DllImport("user32.dll", SetLastError=true)] static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int width, int height, uint flags);
        [DllImport("user32.dll")] static extern int MapWindowPoints(IntPtr from, IntPtr to, ref Point point, uint count);
        [DllImport("user32.dll")] internal static extern bool IsWindow(IntPtr hwnd);
        [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);
        [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hwnd);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder text, int count);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] internal static extern uint RegisterWindowMessage(string name);
        [DllImport("user32.dll")] internal static extern IntPtr RegisterPowerSettingNotification(IntPtr hwnd, ref Guid setting, uint flags);
        [DllImport("user32.dll")] internal static extern bool UnregisterPowerSettingNotification(IntPtr handle);

        // Explorer exposes no public animated-wallpaper attachment API. Keep its
        // window hierarchy handling isolated, and fail instead of covering icons.
        internal static DesktopTarget Discover() {
            var shell=FindWindow("Progman",null);
            if(shell==IntPtr.Zero) throw new InvalidOperationException("The Windows desktop is unavailable. Sign in to a normal desktop session and try again.");
            SendMessageTimeout(shell,0x052C,new IntPtr(13),new IntPtr(1),2,1000,out _);
            var icons=FindWindowEx(shell,IntPtr.Zero,"SHELLDLL_DefView",null);
            var childBackdrop=FindWindowEx(shell,IntPtr.Zero,"WorkerW",null);
            if(icons!=IntPtr.Zero && childBackdrop!=IntPtr.Zero && (GetStyle(shell,-20).ToInt64() & 0x00200000)!=0)
                return new DesktopTarget {Parent=shell,Icons=icons,Underlay=childBackdrop,Layered=true};
            IntPtr background=IntPtr.Zero;
            EnumWindows((top,_)=>{
                if(FindWindowEx(top,IntPtr.Zero,"SHELLDLL_DefView",null)!=IntPtr.Zero) {
                    background=FindWindowEx(IntPtr.Zero,top,"WorkerW",null);
                    return background==IntPtr.Zero;
                }
                return true;
            },IntPtr.Zero);
            if(background==IntPtr.Zero) throw new InvalidOperationException("GroundSurf could not attach behind the desktop icons on this Windows version.");
            return new DesktopTarget {Parent=background};
        }
        internal static void Attach(IntPtr hwnd, Rectangle bounds, DesktopTarget desktop) {
            var style=GetStyle(hwnd,-16).ToInt64();
            SetStyle(hwnd,-16,new IntPtr((style & ~0x80000000L) | 0x40000000L));
            if(desktop.Layered) {
                SetStyle(hwnd,-20,new IntPtr(GetStyle(hwnd,-20).ToInt64() | 0x80000));
                if(!SetLayeredWindowAttributes(hwnd,0,255,2)) throw new System.ComponentModel.Win32Exception();
            }
            SetLastError(0);
            var prior=SetParent(hwnd,desktop.Parent);
            if(prior==IntPtr.Zero && Marshal.GetLastWin32Error()!=0) throw new System.ComponentModel.Win32Exception();
            var point=new Point {X=bounds.Left,Y=bounds.Top};
            MapWindowPoints(IntPtr.Zero,desktop.Parent,ref point,1);
            if(desktop.Layered) SetWindowPos(desktop.Underlay,new IntPtr(1),0,0,0,0,0x13);
            if(!SetWindowPos(hwnd,desktop.Layered ? desktop.Icons : IntPtr.Zero,point.X,point.Y,bounds.Width,bounds.Height,0x10 | 0x40 | 0x20))
                throw new System.ComponentModel.Win32Exception();
        }
        internal static bool CoveredByFullscreen(Rectangle display) {
            var hwnd=GetForegroundWindow();
            if(hwnd==IntPtr.Zero || IsIconic(hwnd))return false;
            var cls=new StringBuilder(256);GetClassName(hwnd,cls,cls.Capacity);
            if(cls.ToString()=="Progman" || cls.ToString()=="WorkerW")return false;
            if(!GetWindowRect(hwnd,out var r))return false;
            return r.Left<=display.Left+2 && r.Top<=display.Top+2 && r.Right>=display.Right-2 && r.Bottom>=display.Bottom-2;
        }
    }
}
