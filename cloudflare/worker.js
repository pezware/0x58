// Serves 0x58 bootstrap scripts on a short, memorable URL:
//
//   bash -c "$(curl -fsSL https://m.pezware.com/linux-start.sh)"
//
// A CNAME cannot do this. raw.githubusercontent.com is virtual-hosted (it serves
// on the Host header and rejects foreign ones), its TLS cert does not cover
// pezware.com, and DNS cannot rewrite a path. So a Worker terminates TLS on our
// hostname, maps the short path to the real one, and proxies the bytes.
//
// Proxy rather than 302: the response needs no -L, keeps the URL you audited in
// the address bar, and lets us set a correct content-type.

const REPO = "pezware/0x58";

// Pin bootstrap scripts to a TAG, not a branch. `curl | bash` against a moving
// branch means the command you ran last month is not the command you run today.
// Bump this deliberately after cutting a release.
const REF = "main";

// Short path -> path in the repo. Explicit allowlist: this Worker must never be
// turned into an open proxy for arbitrary repo contents.
const ROUTES = {
  "/linux-start.sh": "linux/start.sh",
};

export default {
  async fetch(request) {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("method not allowed\n", { status: 405 });
    }

    const url = new URL(request.url);
    const path = ROUTES[url.pathname];
    if (!path) {
      const known = Object.keys(ROUTES).join("\n  ");
      return new Response(`not found\n\navailable:\n  ${known}\n`, { status: 404 });
    }

    const upstream = `https://raw.githubusercontent.com/${REPO}/${REF}/${path}`;
    const res = await fetch(upstream, { cf: { cacheTtl: 300, cacheEverything: true } });

    // Fail loud. A 200 with an error page in the body would be piped straight
    // into bash on the other end.
    if (!res.ok) {
      return new Response(`upstream ${res.status} fetching ${path}\n`, { status: 502 });
    }

    return new Response(res.body, {
      status: 200,
      headers: {
        "content-type": "text/x-shellscript; charset=utf-8",
        "cache-control": "public, max-age=300",
        "x-source": upstream,
      },
    });
  },
};
