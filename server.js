const http = require("http");
const https = require("https");
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

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

function proxyRequest(targetUrl, redirectsLeft = 3) {
  return new Promise((resolve, reject) => {
    const client = targetUrl.startsWith("https") ? https : http;
    const req = client.get(
      targetUrl,
      {
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
          Accept: "*/*",
          "Accept-Encoding": "gzip, deflate, br",
          "Accept-Language": "zh-HK,zh;q=0.9,en-US;q=0.7,en;q=0.6",
        },
        timeout: 15000,
      },
      (res) => {
        const status = res.statusCode || 0;

        if ([301, 302, 303, 307, 308].includes(status) && res.headers.location && redirectsLeft > 0) {
          const nextUrl = new URL(res.headers.location, targetUrl).toString();
          res.resume();
          resolve(proxyRequest(nextUrl, redirectsLeft - 1));
          return;
        }

        const encoding = String(res.headers["content-encoding"] || "").toLowerCase();
        let stream = res;
        if (encoding.includes("br")) stream = res.pipe(zlib.createBrotliDecompress());
        else if (encoding.includes("gzip")) stream = res.pipe(zlib.createGunzip());
        else if (encoding.includes("deflate")) stream = res.pipe(zlib.createInflate());

        const chunks = [];
        let total = 0;
        stream.on("data", (chunk) => {
          chunks.push(chunk);
          total += chunk.length;
          if (total > 8 * 1024 * 1024) req.destroy(new Error("response too large"));
        });

        stream.on("end", () => {
          const body = Buffer.concat(chunks);
          if (status >= 200 && status < 300) {
            const contentType = res.headers["content-type"];
            resolve({ body, contentType });
          } else {
            reject(new Error(`HTTP ${status}: ${body.toString("utf8", 0, 200)}`));
          }
        });

        stream.on("error", reject);
      }
    );

    req.on("timeout", () => req.destroy(new Error("timeout")));
    req.on("error", reject);
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
      res.writeHead(200, { "Content-Type": result?.contentType || "application/octet-stream", "Cache-Control": "no-store" });
      res.end(result.body);
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
