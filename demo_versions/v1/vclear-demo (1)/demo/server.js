// V Clear demo server: db.json = database, uploads/ = files. No dependencies: node server.js
const http=require("http"),fs=require("fs"),path=require("path");
const DB=path.join(__dirname,"db.json"),UP=path.join(__dirname,"uploads"),PUB=path.join(__dirname,"public");
fs.mkdirSync(UP,{recursive:true});
if(!fs.existsSync(DB))fs.writeFileSync(DB,JSON.stringify({counters:{order:0,clinic:0},clinics:[],orders:[]},null,2));
const load=()=>JSON.parse(fs.readFileSync(DB,"utf8"));
const save=d=>{fs.writeFileSync(DB+".tmp",JSON.stringify(d,null,2));fs.renameSync(DB+".tmp",DB)};
const MIME={".html":"text/html",".js":"text/javascript",".pdf":"application/pdf",".jpg":"image/jpeg",".jpeg":"image/jpeg",".png":"image/png",".zip":"application/zip"};
const json=(res,o,c=200)=>{res.writeHead(c,{"Content-Type":"application/json"});res.end(JSON.stringify(o))};
const readBody=req=>new Promise(r=>{let b="";req.on("data",c=>b+=c);req.on("end",()=>r(b?JSON.parse(b):{}))});
function file(res,dir,rel){const f=path.normalize(path.join(dir,rel));
  if(!f.startsWith(dir)||!fs.existsSync(f)||fs.statSync(f).isDirectory()){res.writeHead(404);return res.end("Not found")}
  res.writeHead(200,{"Content-Type":MIME[path.extname(f).toLowerCase()]||"application/octet-stream"});fs.createReadStream(f).pipe(res)}

http.createServer(async(req,res)=>{
  const u=decodeURIComponent(req.url.split("?")[0]);let m;
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
