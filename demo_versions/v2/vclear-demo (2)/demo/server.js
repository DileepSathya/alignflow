// V Clear demo server: db.json = database, uploads/ = files. No dependencies: node server.js
const http=require("http"),fs=require("fs"),path=require("path");
const DB=path.join(__dirname,"db.json"),UP=path.join(__dirname,"uploads"),PUB=path.join(__dirname,"public");
fs.mkdirSync(UP,{recursive:true});
if(!fs.existsSync(DB))fs.writeFileSync(DB,JSON.stringify({counters:{order:0,clinic:0},clinics:[],orders:[]},null,2));
const load=()=>JSON.parse(fs.readFileSync(DB,"utf8"));
// ---- Users (separate file, plain-text passwords: demo only) ----
const USERS=path.join(__dirname,"users.json");
const ROLES=["marketing","cad","lab","qc"];                       // roles the admin can assign
if(!fs.existsSync(USERS))fs.writeFileSync(USERS,JSON.stringify({users:[{username:"admin",password:"admin",name:"Admin",role:"admin",created:new Date().toISOString()}]},null,2));
const loadU=()=>JSON.parse(fs.readFileSync(USERS,"utf8")).users;
const saveU=u=>{fs.writeFileSync(USERS+".tmp",JSON.stringify({users:u},null,2));fs.renameSync(USERS+".tmp",USERS)};
const tokenOf=u=>Buffer.from(u.username+":"+u.password).toString("base64");   // stateless: survives restarts, dies if user/password is removed
const whoIs=req=>{const t=req.headers["x-token"];return t?(loadU().find(u=>tokenOf(u)===t)||null):null};
const pub=u=>({username:u.username,name:u.name,role:u.role});

const save=d=>{fs.writeFileSync(DB+".tmp",JSON.stringify(d,null,2));fs.renameSync(DB+".tmp",DB)};
const MIME={".html":"text/html",".js":"text/javascript",".pdf":"application/pdf",".jpg":"image/jpeg",".jpeg":"image/jpeg",".png":"image/png",".zip":"application/zip"};
const json=(res,o,c=200)=>{res.writeHead(c,{"Content-Type":"application/json"});res.end(JSON.stringify(o))};
const readBody=req=>new Promise(r=>{let b="";req.on("data",c=>b+=c);req.on("end",()=>{try{r(b?JSON.parse(b):{})}catch(e){r({})}})});
function file(res,dir,rel){const f=path.normalize(path.join(dir,rel));
  if(!f.startsWith(dir)||!fs.existsSync(f)||fs.statSync(f).isDirectory()){res.writeHead(404);return res.end("Not found")}
  res.writeHead(200,{"Content-Type":MIME[path.extname(f).toLowerCase()]||"application/octet-stream"});fs.createReadStream(f).pipe(res)}

http.createServer(async(req,res)=>{
  const u=decodeURIComponent(req.url.split("?")[0]);let m;
  if(req.method==="POST"&&u==="/api/login"){                              // {username,password} -> {token,user}
    const b=await readBody(req),un=String(b.username||"").trim().toLowerCase();
    const f=loadU().find(x=>x.username.toLowerCase()===un&&x.password===String(b.password||""));
    return f?json(res,{token:tokenOf(f),user:pub(f)}):json(res,{error:"Invalid username or password"},401);
  }
  if(u.startsWith("/api/")){                                               // everything below needs a signed-in user
    const me=whoIs(req);if(!me)return json(res,{error:"Not signed in"},401);
    if(u==="/api/me")return json(res,{user:pub(me)});
    if(u==="/api/users"||u.startsWith("/api/users/")){                     // admin only
      if(me.role!=="admin")return json(res,{error:"Admin only"},403);
      if(req.method==="GET"&&u==="/api/users")return json(res,{users:loadU()});
      if(req.method==="POST"&&u==="/api/users"){
        const b=await readBody(req),list=loadU();
        const un=String(b.username||"").trim(),pw=String(b.password||""),nm=String(b.name||"").trim(),role=String(b.role||"");
        if(!nm)return json(res,{error:"Enter the person's full name."},400);
        if(!/^[A-Za-z0-9._-]{2,30}$/.test(un))return json(res,{error:"Username must be 2-30 characters: letters, numbers, dot, dash or underscore."},400);
        if(!pw)return json(res,{error:"Enter a password."},400);
        if(!ROLES.includes(role))return json(res,{error:"Choose a role."},400);
        if(list.some(x=>x.username.toLowerCase()===un.toLowerCase()))return json(res,{error:"That username is already taken."},409);
        const nu={username:un,password:pw,name:nm,role,created:new Date().toISOString()};list.push(nu);saveU(list);
        return json(res,{user:nu});
      }
      let mu;
      if(req.method==="DELETE"&&(mu=u.match(/^\/api\/users\/([^/]+)$/))){
        const list=loadU(),i=list.findIndex(x=>x.username===mu[1]);
        if(i<0)return json(res,{error:"User not found"},404);
        if(list[i].role==="admin")return json(res,{error:"The admin account can't be deleted."},400);
        list.splice(i,1);saveU(list);return json(res,{ok:true});
      }
      return json(res,{error:"Not found"},404);
    }
  }
  if(u==="/api/db")return json(res,load());
  if(req.method==="POST"&&(m=u.match(/^\/api\/next\/(order|clinic)$/))){   // ORD-001, CLC-001 ...
    const d=load(),n=++d.counters[m[1]];save(d);
    return json(res,{id:(m[1]==="order"?"ORD-":"CLC-")+String(n).padStart(3,"0")});
  }
  if(req.method==="PATCH"&&(m=u.match(/^\/api\/(orders|clinics)\/([^/]+)$/))){  // merge only the changed fields
    const patch=await readBody(req),d=load(),list=d[m[1]];let r=list.find(x=>x.id===m[2]);
    if(!r){r={id:m[2]};if(m[1]==="orders")Object.assign(r,{plan:0,lab:0,qcOk:0,issue:false,cycles:0});list.unshift(r)}
    Object.assign(r,patch);save(d);return json(res,{ok:true});
  }
  if(req.method==="POST"&&u==="/api/upload"){                            // raw body -> uploads/
    const name=Date.now()+"-"+decodeURIComponent(req.headers["x-filename"]||"file").replace(/[^\w.\- ]/g,"_");
    const w=fs.createWriteStream(path.join(UP,name));req.pipe(w);
    w.on("finish",()=>json(res,{url:"/uploads/"+encodeURIComponent(name)}));return;
  }
  if(u.startsWith("/uploads/"))return file(res,UP,u.slice(9));
  file(res,PUB,u==="/"?"index.html":u.slice(1));
}).listen(3000,()=>console.log("Demo running: http://localhost:3000"));
