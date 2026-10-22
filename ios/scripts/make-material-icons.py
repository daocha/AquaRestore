# Regenerates ios/AquaRestore/App/MaterialIcons.swift from the material-icons sources jars (unpacked under /tmp/m3src/icons).

import re, math, sys
R='/tmp/m3src/icons/commonMain/androidx/compose/material/icons/rounded/'
names = ["Close","SwapHoriz","FileDownload","Settings","Speed","ExpandLess","ExpandMore","ContentCut","MusicNote","LibraryMusic",
         "AutoAwesome","AddPhotoAlternate","Tune","HighQuality","FullscreenExit","Fullscreen","Compare","FirstPage","LastPage","PlayArrow","Pause"]

def arc_to_beziers(x1,y1,rx,ry,phi,fa,fs,x2,y2):
    # SVG arc endpoint parameterization -> cubic beziers (absolute)
    if rx == 0 or ry == 0: return [('L',x2,y2)]
    if x1==x2 and y1==y2: return []
    phi=math.radians(phi); c=math.cos(phi); s=math.sin(phi)
    dx=(x1-x2)/2; dy=(y1-y2)/2
    x1p=c*dx+s*dy; y1p=-s*dx+c*dy
    rx=abs(rx); ry=abs(ry)
    lam=(x1p*x1p)/(rx*rx)+(y1p*y1p)/(ry*ry)
    if lam>1: rx*=math.sqrt(lam); ry*=math.sqrt(lam)
    num=rx*rx*ry*ry-rx*rx*y1p*y1p-ry*ry*x1p*x1p
    den=rx*rx*y1p*y1p+ry*ry*x1p*x1p
    co=math.sqrt(max(0,num/den)) if den else 0
    if fa==fs: co=-co
    cxp=co*rx*y1p/ry; cyp=-co*ry*x1p/rx
    cx=c*cxp-s*cyp+(x1+x2)/2; cy=s*cxp+c*cyp+(y1+y2)/2
    def ang(ux,uy,vx,vy):
        a=math.atan2(ux*vy-uy*vx, ux*vx+uy*vy); return a
    t1=ang(1,0,(x1p-cxp)/rx,(y1p-cyp)/ry)
    dt=ang((x1p-cxp)/rx,(y1p-cyp)/ry,(-x1p-cxp)/rx,(-y1p-cyp)/ry)
    if not fs and dt>0: dt-=2*math.pi
    elif fs and dt<0: dt+=2*math.pi
    n=max(1,int(math.ceil(abs(dt)/(math.pi/2)-1e-9)))
    d=dt/n; out=[]
    k=4/3*math.tan(d/4)
    t=t1
    for i in range(n):
        ct,st=math.cos(t),math.sin(t); ct2,st2=math.cos(t+d),math.sin(t+d)
        p1=(ct-k*st, st+k*ct); p2=(ct2+k*st2, st2-k*ct2); p3=(ct2,st2)
        def m(p):
            x=rx*p[0]; y=ry*p[1]
            return (c*x-s*y+cx, s*x+c*y+cy)
        a,b,e=m(p1),m(p2),m(p3)
        out.append(('C',a[0],a[1],b[0],b[1],e[0],e[1]))
        t+=d
    return out

def convert(name):
    src=open(R+name+'.kt').read()
    body=src[src.index('materialPath {'):src.rindex('return _')]
    calls=re.findall(r'(\w+)\(([^()]*)\)', body)
    out=[]; cx=cy=0; sx=sy=0; lc=None
    def f(v): return float(v.strip().rstrip('f')) if v.strip() not in ('true','false') else (v.strip()=='true')
    for fn,args in calls:
        a=[f(x) for x in args.split(',')] if args.strip() else []
        if fn=='materialPath' or fn=='materialIcon': continue
        if fn=='moveTo': cx,cy=a; sx,sy=cx,cy; out.append(('M',cx,cy)); lc=None
        elif fn=='moveToRelative': cx+=a[0]; cy+=a[1]; sx,sy=cx,cy; out.append(('M',cx,cy)); lc=None
        elif fn=='lineTo': cx,cy=a; out.append(('L',cx,cy)); lc=None
        elif fn=='lineToRelative': cx+=a[0]; cy+=a[1]; out.append(('L',cx,cy)); lc=None
        elif fn=='horizontalLineTo': cx=a[0]; out.append(('L',cx,cy)); lc=None
        elif fn=='horizontalLineToRelative': cx+=a[0]; out.append(('L',cx,cy)); lc=None
        elif fn=='verticalLineTo': cy=a[0]; out.append(('L',cx,cy)); lc=None
        elif fn=='verticalLineToRelative': cy+=a[0]; out.append(('L',cx,cy)); lc=None
        elif fn in ('curveTo','curveToRelative'):
            o=(cx,cy) if fn.endswith('Relative') else (0,0)
            x1,y1,x2,y2,x,y=a[0]+o[0],a[1]+o[1],a[2]+o[0],a[3]+o[1],a[4]+o[0],a[5]+o[1]
            out.append(('C',x1,y1,x2,y2,x,y)); lc=(x2,y2); cx,cy=x,y
        elif fn in ('reflectiveCurveTo','reflectiveCurveToRelative'):
            o=(cx,cy) if fn.endswith('Relative') else (0,0)
            x1,y1=(2*cx-lc[0],2*cy-lc[1]) if lc else (cx,cy)
            x2,y2,x,y=a[0]+o[0],a[1]+o[1],a[2]+o[0],a[3]+o[1]
            out.append(('C',x1,y1,x2,y2,x,y)); lc=(x2,y2); cx,cy=x,y
        elif fn in ('arcTo','arcToRelative'):
            rx,ry,th,large,sweep,x,y=a
            if fn.endswith('Relative'): x+=cx; y+=cy
            out+=arc_to_beziers(cx,cy,rx,ry,th,large,sweep,x,y); cx,cy=x,y; lc=None
        elif fn=='close': out.append(('Z',)); cx,cy=sx,sy; lc=None
        else: raise Exception('unknown '+fn+' in '+name)
    def num(v):
        s=('%.3f'%v).rstrip('0').rstrip('.')
        return '0' if s in ('-0','') else s
    return ' '.join(c[0]+(' '+' '.join(num(v) for v in c[1:]) if len(c)>1 else '') for c in out)

lines=[]
for n in names:
    case=n[0].lower()+n[1:]
    lines.append('        case .%s: return "%s"' % (case, convert(n)))
cases=', '.join(n[0].lower()+n[1:] for n in names)
print('''import SwiftUI

/// Material Icons (Rounded, 1.7.8), the set the Android app uses, drawn from their own 24 x 24 path data.
/// Generated from the androidx.compose.material:material-icons-extended sources (Apache License 2.0).
enum MaterialIcon {
    case %s

    var data: String {
        switch self {
%s
        }
    }

    private static var cache: [String: Path] = [:]
    private static let lock = NSLock()
    var path: Path {
        let key = data
        MaterialIcon.lock.lock(); defer { MaterialIcon.lock.unlock() }
        if let path = MaterialIcon.cache[key] { return path }
        let path = SVGPath.parse(key)
        MaterialIcon.cache[key] = path
        return path
    }
}

/// A 24-unit Material icon scaled to `size` (Compose's default icon size is 24). Without an explicit color it
/// takes the inherited content color, like Compose's LocalContentColor.
struct MIcon: View {
    @Environment(\.contentColor) private var inherited
    let icon: MaterialIcon
    var size: CGFloat = 24
    var color: Color? = nil
    init(_ icon: MaterialIcon, size: CGFloat = 24, color: Color? = nil) { self.icon = icon; self.size = size; self.color = color }
    var body: some View {
        IconShape(path: icon.path)
            .fill(color ?? inherited)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct IconShape: Shape {
    let path: Path
    var viewport: CGFloat = 24
    func path(in rect: CGRect) -> Path {
        path.applying(CGAffineTransform(scaleX: rect.width / viewport, y: rect.height / viewport).translatedBy(x: rect.minX, y: rect.minY))
    }
}
''' % (cases, '\n'.join(lines)))
