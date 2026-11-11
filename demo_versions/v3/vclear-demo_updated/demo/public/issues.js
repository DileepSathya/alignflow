// Shared: order-centric Issues section + equal, scrollable Documents / Comments layout
(function(){
  var st=document.createElement("style");st.textContent=[
  ".grid2.docs{grid-template-columns:1fr 1fr!important;align-items:stretch!important}",
  ".grid2.docs>.card{display:flex;flex-direction:column;height:460px}",
  ".grid2.docs>.card .dl,.grid2.docs>.card .cms,.grid2.docs>.card .nocm{flex:1 1 auto;min-height:0;overflow-y:auto}",
  ".grid2.docs>.card .card-h,.grid2.docs>.card .hint,.grid2.docs>.card .dz,.grid2.docs>.card .cform{flex:none}",
  ".issues{margin-top:20px;background:var(--surface,#fff);border:1px solid var(--line,#e3e8e6);border-radius:14px;overflow:hidden}",
  ".issues .card-h{display:flex;align-items:center;gap:8px;padding:14px 18px;font-weight:600}",
  ".issues .card-h .n{margin-left:8px;font-size:12px;background:#eef2f1;border-radius:99px;padding:2px 8px}",
  ".iss{border-top:1px solid var(--line,#e3e8e6);padding:16px 18px}",
  ".iss-top{display:flex;flex-wrap:wrap;align-items:center;gap:10px;margin-bottom:12px}.iss-top b{font-size:14px}",
  ".iss .tag{font-size:11px;font-weight:600;border-radius:99px;padding:3px 10px}.iss .tag.open{background:#fdecea;color:#b42318}.iss .tag.done{background:#e3f4ee;color:#0b6b57}.iss .tag.stg{background:#eef2f1;color:#445}",
  ".iss-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px 20px;margin:0 0 12px}.iss-grid div{min-width:0}",
  ".iss-grid dt{font-size:11px;text-transform:uppercase;letter-spacing:.04em;opacity:.6;margin-bottom:2px}.iss-grid dd{margin:0;font-size:13.5px}.iss-grid dd small{display:block;opacity:.65}",
  ".iss-note{background:#f7f9f8;border:1px solid var(--line,#e3e8e6);border-radius:10px;padding:10px 12px;margin:0 0 10px;font-size:14px;white-space:pre-wrap}",
  ".iss-files{list-style:none;margin:0 0 10px;padding:0;display:flex;flex-wrap:wrap;gap:8px}.iss-files li{display:flex;align-items:center;gap:8px;border:1px solid var(--line,#e3e8e6);border-radius:10px;padding:6px 10px;font-size:12.5px}",
  ".iss-files a{color:#0f766e;text-decoration:none;font-weight:600}",
  ".iss-act{display:flex;align-items:center;gap:12px;flex-wrap:wrap}.iss-act small{opacity:.65}",
  ".ibtn{background:#0f766e;color:#fff;border:0;border-radius:10px;padding:9px 16px;font:inherit;font-weight:600;cursor:pointer}.ibtn:hover{filter:brightness(1.1)}",
  "@media (max-width:720px){.iss-grid{grid-template-columns:1fr 1fr}.grid2.docs>.card{height:380px}}",
  /* status bar: collapsed issue step ("+" icon) and jump target */
  ".issues{scroll-margin-top:16px}",
  ".issues.flash{animation:issflash 1.6s ease-out}",
  "@keyframes issflash{0%{box-shadow:0 0 0 3px var(--accent,#0b7a75)}100%{box-shadow:0 0 0 3px transparent}}",
  ".stp .dot.plus{display:grid;place-items:center;width:18px;height:18px;border-radius:50%;border:2px solid var(--line,#d8e2e6);background:var(--surface,#fff);color:var(--ink-2,#4a6068);position:relative;z-index:1;text-decoration:none;cursor:pointer;transition:transform .12s}",
  ".stp .dot.plus::before{content:'';position:absolute;inset:-8px}",
  ".stp .dot.plus::after{display:none!important}",
  ".stp .dot.plus:hover{transform:scale(1.18)}",
  ".stp .dot.plus svg{display:block;pointer-events:none}",
  ".stp.done .dot.plus{background:var(--accent,#0b7a75);border-color:var(--accent,#0b7a75);color:#fff}",
  ".stp.current .dot.plus{border-color:var(--accent,#0b7a75);color:var(--accent,#0b7a75);box-shadow:0 0 0 4px var(--accent-soft,#d9efed)}",
  ".stp.issue .dot.plus{border-color:var(--danger,#b3261e);color:var(--danger,#b3261e);box-shadow:0 0 0 4px #fbe0dd;background:#fff}",
  ".stp small.sn{display:block;font-weight:600;font-size:10.5px;margin-top:2px;color:inherit;opacity:.85}",
  "@media (prefers-reduced-motion:reduce){.issues.flash{animation:none}}"].join("\n");
  document.head.appendChild(st);
  function esc(s){var d=document.createElement("div");d.textContent=s==null?"":String(s);return d.innerHTML}
  function dt(d){d=new Date(d);return d.getDate()+" "+d.toLocaleString("en-GB",{month:"short"})+" "+d.getFullYear()+", "+d.toLocaleTimeString("en-US",{hour:"numeric",minute:"2-digit"})}
  function kb(n){return n>=1048576?(n/1048576).toFixed(1)+" MB":Math.max(1,Math.round(n/1024))+" KB"}
  function who(p){return p?(p.name===p.team?'<dd>'+esc(p.team)+'</dd>':'<dd>'+esc(p.name)+'<small>'+esc(p.team)+'</small></dd>'):'<dd>-</dd>'}
  var cfg;
  var PLUS='<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="4.5" stroke-linecap="round"><path d="M12 4v16M4 12h16"/></svg>';
  // "+" step icons jump to the Issues section without touching location.hash (the pages use the hash for routing)
  document.addEventListener("click",function(e){
    var a=e.target.closest&&e.target.closest("[data-jump]");if(!a)return;
    var t=document.getElementById(a.getAttribute("data-jump"));e.preventDefault();if(!t)return;
    var calm=window.matchMedia&&matchMedia("(prefers-reduced-motion:reduce)").matches;
    t.scrollIntoView({behavior:calm?"auto":"smooth",block:"start"});
    t.classList.remove("flash");void t.offsetWidth;t.classList.add("flash");
  });
  window.VI={
    // number of issues raised on this order (optionally for one stage: "clinic" | "qc")
    count:function(o,stage){return (o.issues||[]).filter(function(i){return !stage||i.stage===stage}).length},
    // one status-bar step. With more than one issue the dot becomes a "+" link to the Issues section.
    stp:function(cls,label,sub,n){
      var dot=n>1?'<a class="dot plus" href="#issues" data-jump="issues" title="'+n+' issues raised: jump to the Issues section" aria-label="'+n+' issues raised, jump to the Issues section">'+PLUS+'</a>':'<span class="dot"></span>';
      return '<li class="stp '+cls+'">'+dot+'<span>'+esc(label)+(sub?'<small class="onlyif">'+esc(sub)+'</small>':'')+(n>1?'<small class="sn">'+n+' issues &middot; view</small>':'')+'</span></li>';
    },
    init:function(c){cfg=c;
      document.getElementById("view").addEventListener("click",function(e){
        var b=e.target.closest("[data-iact]");if(!b)return;
        var o=cfg.get(b.getAttribute("data-oid"));if(!o)return;
        var i=(o.issues||[]).filter(function(x){return x.id===b.getAttribute("data-iss")})[0];
        if(!i||i.resolvedAt||!i.raisedTo||i.raisedTo.team!==cfg.team)return;      // only the team it was raised to
        i.resolvedAt=new Date();i.resolvedBy={name:cfg.me,team:cfg.team};
        if(cfg.onResolve)cfg.onResolve(o,i);cfg.render(o);cfg.toast("Issue marked as resolved");
      });},
    section:function(o){
      var all=o.issues||[],open=all.filter(function(i){return !i.resolvedAt}).length;
      var body=!all.length?'<p style="padding:0 18px 18px;margin:0;opacity:.65">No issues have been raised for this order.</p>':
      all.map(function(i,k){return [i,k+1]}).reverse().map(function(p){var i=p[0],n=p[1],can=!i.resolvedAt&&i.raisedTo&&i.raisedTo.team===cfg.team;
        return '<article class="iss"><div class="iss-top"><b>Issue #'+n+'</b><span class="tag '+(i.resolvedAt?'done':'open')+'">'+(i.resolvedAt?'Resolved':'Open')+'</span><span class="tag stg">'+(i.stage==="qc"?"QC check":"Clinician review")+'</span></div>'+
        '<dl class="iss-grid"><div><dt>Raised by</dt>'+who(i.raisedBy)+'</div><div><dt>Raised to</dt>'+who(i.raisedTo)+'</div>'+
        '<div><dt>Raised on</dt><dd>'+dt(i.raisedAt)+'</dd></div><div><dt>Resolved on</dt><dd>'+(i.resolvedAt?dt(i.resolvedAt)+'<small>by '+esc(i.resolvedBy&&i.resolvedBy.name)+'</small>':'Not resolved yet')+'</dd></div></dl>'+
        '<p class="iss-note">'+esc(i.text)+'</p>'+
        ((i.files||[]).length?'<ul class="iss-files">'+i.files.map(function(f){return '<li><span>'+esc(f.name)+' &middot; '+kb(f.size)+'</span><a href="'+esc(f.url)+'" target="_blank">View</a><a href="'+esc(f.url)+'" download="'+esc(f.name)+'">Download</a></li>'}).join("")+'</ul>':'')+
        (can?'<div class="iss-act"><button class="ibtn" data-iact="resolve" data-oid="'+esc(o.id)+'" data-iss="'+esc(i.id)+'">Mark issue resolved</button></div>':
         (!i.resolvedAt?'<div class="iss-act"><small>Only the '+esc(i.raisedTo&&i.raisedTo.team)+' can mark this resolved.</small></div>':''))+'</article>'}).join("");
      return '<section class="issues" id="issues"><div class="card-h"><span>Issues<span class="n">'+all.length+(open?' &middot; '+open+' open':'')+'</span></span></div>'+body+'</section>';
    }
  };
})();
