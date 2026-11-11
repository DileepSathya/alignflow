// Shared login guard. Session lives in sessionStorage, so each browser tab can be a different user.
// Usage: <script src="auth.js" data-role="marketing"></script>  (data-public = login page, no guard)
(function(){
  var ROLES={
    admin:    {label:"Admin",               team:"Admin",             rail:"Administrator",              home:"admin.html"},
    marketing:{label:"Marketing",           team:"Marketing team",    rail:"Marketing team",             home:"marketing.html"},
    cad:      {label:"Clinical CAD",        team:"Clinical CAD team", rail:"Clinical CAD team",          home:"planner.html"},
    lab:      {label:"Lab / Manufacturing", team:"Lab team",          rail:"Lab & Manufacturing team",   home:"lab.html"},
    qc:       {label:"QC",                  team:"QC team",           rail:"QC team",                    home:"qc.html"}
  };
  var cs=document.currentScript,need=cs&&cs.getAttribute("data-role"),pub=cs&&cs.hasAttribute("data-public");
  var user=null;try{user=JSON.parse(sessionStorage.getItem("vc_user")||"null")}catch(e){}
  if(user&&(!ROLES[user.role]||!sessionStorage.getItem("vc_token")))user=null;

  function esc(s){var d=document.createElement("div");d.textContent=s==null?"":String(s);return d.innerHTML}
  function clear(){try{sessionStorage.removeItem("vc_user");sessionStorage.removeItem("vc_token")}catch(e){}}
  var A=window.VAuth={
    ROLES:ROLES,ok:true,user:user||{name:"",username:"",role:""},
    token:function(){return sessionStorage.getItem("vc_token")||""},
    login:function(res){sessionStorage.setItem("vc_token",res.token);sessionStorage.setItem("vc_user",JSON.stringify(res.user));location.replace(ROLES[res.user.role].home)},
    logout:function(){clear();location.replace("login.html")},
    expired:function(){clear();location.replace("login.html")},
    home:function(){return user?ROLES[user.role].home:"login.html"}
  };

  if(pub)return;
  if(!user){A.ok=false;location.replace("login.html");return}
  if(need&&user.role!==need){A.ok=false;location.replace(ROLES[user.role].home);return}

  // Fill the sidebar identity box and add a Log out button
  var r=ROLES[user.role],ini=user.name.split(/\s+/).filter(Boolean).slice(0,2).map(function(w){return w[0].toUpperCase()}).join("")||"?";
  var box=document.querySelector(".role");
  if(box)box.innerHTML='<div class="avatar">'+esc(ini)+'</div><div><span>'+esc(user.name)+'</span><small>'+esc(r.rail)+'</small></div>';
  var rail=document.getElementById("rail");
  if(rail&&!rail.querySelector(".rail-foot")){
    var f=document.createElement("div");f.className="rail-foot";
    f.innerHTML='<button type="button" class="btn ghost" id="vcLogout" style="width:100%;justify-content:center">Log out</button>';
    rail.appendChild(f);f.querySelector("button").addEventListener("click",A.logout);
  }
})();
