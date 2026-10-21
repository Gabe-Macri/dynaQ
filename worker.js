export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Root path rewrite to /index.html
    if (url.pathname === "/" || url.pathname === "") {
      return env.ASSETS.fetch(new Request(new URL("/index.html", request.url), request));
    }

    // Forward request to Cloudflare Static Assets binding
    return env.ASSETS.fetch(request);
  }
};
