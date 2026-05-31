const http = require("http");
const https = require("https");
const fs = require("fs");
const path = require("path");

const PORT = process.env.PORT || 8080;
const ROOT = __dirname;

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".json": "application/json",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".ico": "image/x-icon",
};

function proxyRequest(targetUrl) {
  return new Promise((resolve, reject) => {
    const client = targetUrl.startsWith("https") ? https : http;
    client.get(targetUrl, { headers: { "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36", "Accept": "application/json" } }, (res) => {
      let data = "";
      res.on("data", (chunk) => (data += chunk));
      res.on("end", () => {
        if (res.statusCode >= 200 && res.statusCode < 300) resolve(data);
        else reject(new Error(`HTTP ${res.statusCode}: ${data.slice(0, 100)}`));
      });
    }).on("error", reject);
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);

  try {
    res.setHeader("Access-Control-Allow-Origin", "*");

    if (url.pathname === "/api/proxy") {
      const target = url.searchParams.get("url");
      if (!target) {
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "missing url param" }));
        return;
      }
      const result = await proxyRequest(target);
      res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
      res.end(result);
      console.log(`  [OK] ${target.slice(0, 55)}...`);
      return;
    }

    const filePath = url.pathname === "/" ? path.join(ROOT, "daily.html") : path.join(ROOT, url.pathname);
    if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
      const ext = path.extname(filePath);
      const contentType = MIME[ext] || "application/octet-stream";
      const content = fs.readFileSync(filePath);
      res.writeHead(200, { "Content-Type": contentType, "Content-Length": content.length });
      res.end(content);
    } else {
      res.writeHead(404);
      res.end("Not Found");
    }
  } catch (e) {
    console.error(`  [ERR] ${e.message}`);
    res.writeHead(500);
    res.end("Internal Server Error");
  }
});

server.listen(PORT, () => {
  console.log("======================================");
  console.log("  Server started on Google Cloud Run!");
  console.log(`  Port: ${PORT}`);
  console.log("======================================");
});
