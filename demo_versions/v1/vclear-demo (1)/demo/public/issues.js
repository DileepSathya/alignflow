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
  "@media (max-width:720px){.iss-grid{grid-template-columns:1fr 1fr}.grid2.docs>.card{height:380px}}"].join("\n");
  document.head.appendChild(st);
  function esc(s){var d=document.createElement("div");d.textContent=s==null?"":String(s);return d.innerHTML}
  function dt(d){d=new Date(d);return d.getDate()+" "+d.toLocaleString("en-GB",{month:"short"})+" "+d.getFullYear()+", "+d.toLocaleTimeString("en-US",{hour:"numeric",minute:"2-digit"})}
  function kb(n){return n>=1048576?(n/1048576).toFixed(1)+" MB":Math.max(1,Math.round(n/1024))+" KB"}
  function who(p){return p?'<dd>'+esc(p.name)+'<small>'+esc(p.team)+'</small></dd>':'<dd>-</dd>'}
  var cfg;
  window.VI={
    init:function(c){cfg=c;
      document.getElementById("view").addEventListener("click",function(e){
        var b=e.target.closest("[data-iact]");if(!b)return;
        var o=cfg.get(b.getAttribute("data-oid"));if(!o)return;
        var i=(o.issues||[]).filter(function(x){return x.id===b.getAttribute("data-iss")})[0];
        if(!i||i.resolvedAt||!i.raisedTo||i.raisedTo.name!==cfg.me)return;      // only the person it was raised to
        i.resolvedAt=new Date();i.resolvedBy={name:cfg.me,team:cfg.team};
        if(cfg.onResolve)cfg.onResolve(o,i);cfg.render(o);cfg.toast("Issue marked as resolved");
      });},
    section:function(o){
      var all=o.issues||[],open=all.filter(function(i){return !i.resolvedAt}).length;
      var body=!all.length?'<p style="padding:0 18px 18px;margin:0;opacity:.65">No issues have been raised for this order.</p>':
      all.map(function(i,k){return [i,k+1]}).reverse().map(function(p){var i=p[0],n=p[1],can=!i.resolvedAt&&i.raisedTo&&i.raisedTo.name===cfg.me;
        return '<article class="iss"><div class="iss-top"><b>Issue #'+n+'</b><span class="tag '+(i.resolvedAt?'done':'open')+'">'+(i.resolvedAt?'Resolved':'Open')+'</span><span class="tag stg">'+(i.stage==="qc"?"QC check":"Clinician review")+'</span></div>'+
        '<dl class="iss-grid"><div><dt>Raised by</dt>'+who(i.raisedBy)+'</div><div><dt>Raised to</dt>'+who(i.raisedTo)+'</div>'+
        '<div><dt>Raised on</dt><dd>'+dt(i.raisedAt)+'</dd></div><div><dt>Resolved on</dt><dd>'+(i.resolvedAt?dt(i.resolvedAt)+'<small>by '+esc(i.resolvedBy&&i.resolvedBy.name)+'</small>':'Not resolved yet')+'</dd></div></dl>'+
        '<p class="iss-note">'+esc(i.text)+'</p>'+
        ((i.files||[]).length?'<ul class="iss-files">'+i.files.map(function(f){return '<li><span>'+esc(f.name)+' &middot; '+kb(f.size)+'</span><a href="'+esc(f.url)+'" target="_blank">View</a><a href="'+esc(f.url)+'" download="'+esc(f.name)+'">Download</a></li>'}).join("")+'</ul>':'')+
        (can?'<div class="iss-act"><button class="ibtn" data-iact="resolve" data-oid="'+esc(o.id)+'" data-iss="'+esc(i.id)+'">Mark issue resolved</button></div>':
         (!i.resolvedAt?'<div class="iss-act"><small>Only '+esc(i.raisedTo&&i.raisedTo.name)+' ('+esc(i.raisedTo&&i.raisedTo.team)+') can mark this resolved.</small></div>':''))+'</article>'}).join("");
      return '<section class="issues"><div class="card-h"><span>Issues<span class="n">'+all.length+(open?' &middot; '+open+' open':'')+'</span></span></div>'+body+'</section>';
    }
  };
})();
