// Serves the Noema web build at noema.dkentbrown.dev (deploy with web/deploy.sh).
// Static files come straight from the assets directory. The one exception is the engine,
// index.wasm: at ~38 MB it is over Cloudflare's 25 MiB per-file limit, so deploy.sh ships it
// gzipped as index.wasm.gz and this hands that file out under the original name with
// Content-Encoding: gzip; the browser decompresses it as it downloads.
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/index.wasm") {
      const gz = await env.ASSETS.fetch(new Request(new URL("/index.wasm.gz", url), request));
      if (!gz.ok) return gz;
      const headers = new Headers(gz.headers);
      headers.set("Content-Type", "application/wasm");
      headers.set("Content-Encoding", "gzip");
      headers.delete("Content-Length");
      return new Response(gz.body, { status: 200, headers, encodeBody: "manual" });
    }
    return env.ASSETS.fetch(request);
  },
};
