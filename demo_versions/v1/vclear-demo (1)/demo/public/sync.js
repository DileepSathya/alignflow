// Shared data layer: pages keep their own arrays; this syncs them with the server every 1.5s.
(function(){
  var STAGE=["plan","lab","qcOk","issue","cycles","cadBy","labBy"];
  function jc(x){return JSON.stringify(x,function(k,v){if(v&&typeof v==="object"&&!Array.isArray(v)){var o={};Object.keys(v).sort().forEach(function(a){o[a]=v[a]});return o}return v})}
  function clone(x){return JSON.parse(jc(x))}
  function rev(c){var o=clone(c);if(o.created)o.created=new Date(o.created);
    (o.docs||[]).concat(o.comments||[]).forEach(function(x){if(x.at)x.at=new Date(x.at)});
    (o.issues||[]).forEach(function(i){if(i.raisedAt)i.raisedAt=new Date(i.raisedAt);if(i.resolvedAt)i.resolvedAt=new Date(i.resolvedAt);(i.files||[]).forEach(function(f){if(f.at)f.at=new Date(f.at)})});return o}
  function sx(m,u,body,hdr){var x=new XMLHttpRequest();x.open(m,u,false);for(var k in hdr||{})x.setRequestHeader(k,hdr[k]);x.send(body);return JSON.parse(x.responseText)}
  function diff(c,p){var d={},n=0;for(var k in c){if(c[k]===undefined)continue;if(!p||jc(c[k])!==jc(p[k])){d[k]=c[k];n++}}return n?d:null}

  window.VSync=function(cfg){
    var last={orders:{},clinics:{}},dirty=false,busy=false;
    function toC(o){var c={},k;for(k in o)if(cfg.LOCAL.indexOf(k)<0)c[k]=o[k];var s=cfg.OUT(o);for(k in s)if(s[k]!==undefined)c[k]=s[k];return c}
    function fromC(c){var o={},k;for(k in c)if(STAGE.indexOf(k)<0)o[k]=c[k];var s=cfg.IN(c);for(k in s)o[k]=s[k];return rev(o)}
    var ident=function(x){return x};
    var kinds=[["orders",cfg.orders,toC,fromC,cfg.vis],["clinics",cfg.clinics,ident,rev,null]];

    function merge(db){var changed=false;
      kinds.forEach(function(t){var kind=t[0],loc=t[1],L=last[kind],out=[];
        db[kind].forEach(function(sc){
          if(t[4]&&!t[4](sc))return;
          var l=loc.filter(function(x){return x.id===sc.id})[0];
          if(l&&diff(t[2](l),L[sc.id])){out.push(l);return}          // local edit not pushed yet: keep it
          if(l&&!diff(sc,L[sc.id])){out.push(l);return}               // nothing new from server
          L[sc.id]=clone(sc);out.push(t[3](sc));changed=true;
        });
        if(out.length!==loc.length)changed=true;
        Array.prototype.splice.apply(loc,[0,loc.length].concat(out));
      });return changed}

    function push(){var ps=[];
      kinds.forEach(function(t){t[1].forEach(function(o){
        var c=t[2](o),d=diff(c,last[t[0]][o.id]);if(!d)return;
        last[t[0]][o.id]=Object.assign(last[t[0]][o.id]||{},clone(d));
        ps.push(fetch("/api/"+t[0]+"/"+encodeURIComponent(o.id),{method:"PATCH",headers:{"Content-Type":"application/json"},body:jc(d)}));
      })});return Promise.all(ps)}

    function tick(){if(busy)return;busy=true;
      push().then(function(){return fetch("/api/db").then(function(r){return r.json()})})
        .then(function(db){if(merge(db))dirty=true;if(dirty&&cfg.render()!==false)dirty=false})
        .catch(function(){}).then(function(){busy=false})}

    merge(sx("GET","/api/db"));                 // first load is synchronous, so the page starts with real data
    setInterval(tick,1500);
    return {
      nid:function(kind){return sx("POST","/api/next/"+kind).id},
      upload:function(f){return sx("POST","/api/upload",f,{"X-Filename":encodeURIComponent(f.name)}).url}
    };
  };
})();
