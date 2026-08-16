// Supabase Edge Function: scrape-card
// Server-side proxy to bypass CORS restrictions when scraping bank credit card pages
// from the Flutter Web frontend.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { url } = await req.json();

    if (!url || typeof url !== "string") {
      return new Response(
        JSON.stringify({ error: "Missing or invalid 'url' parameter" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Validate URL is a legitimate bank/financial website
    const parsedUrl = new URL(url);
    const allowedDomains = [
      "axisbank.com",
      "axis.bank.in",
      "hdfcbank.com",
      "hdfc.bank.in",
      "icicibank.com",
      "icici.bank.in",
      "sbicard.com",
      "kotak.com",
      "kotak.bank.in",
      "idfcfirstbank.com",
      "idfcfirst.bank.in",
      "aubank.in",
      "au.bank.in",
      "yesbank.in",
      "yes.bank.in",
      "indusind.com",
      "indusind.bank.in",
      "rbl.bank",
      "rblbank.com",
      "bobfinancial.com",
      "sc.com", // Standard Chartered
      "hsbc.co.in",
      "citibank.com",
      "americanexpress.com",
      "google.com", // For Google Search fallback
    ];

    const hostname = parsedUrl.hostname.toLowerCase();
    const isDomainAllowed = allowedDomains.some(
      (domain) =>
        hostname === domain || hostname.endsWith(`.${domain}`) ||
        hostname === `www.${domain}`,
    );

    if (!isDomainAllowed) {
      return new Response(
        JSON.stringify({ error: `Domain not allowed: ${hostname}` }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Fetch the page server-side (no CORS restrictions on server)
    const fetchHeaders: Record<string, string> = {
      "User-Agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      "Accept":
        "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
      "Accept-Language": "en-US,en;q=0.5",
      "Connection": "keep-alive",
      "Upgrade-Insecure-Requests": "1",
    };

    let currentUrl = url;
    let response: Response | null = null;
    for (let redirects = 0; redirects <= 4; redirects++) {
      const candidate = new URL(currentUrl);
      const candidateHost = candidate.hostname.toLowerCase();
      const allowed = allowedDomains.some(
        (domain) => candidateHost === domain || candidateHost.endsWith(`.${domain}`),
      );
      if (candidate.protocol !== "https:" || !allowed) {
        throw new Error(`Redirect target not allowed: ${candidateHost}`);
      }
      response = await fetch(currentUrl, {
        headers: fetchHeaders,
        redirect: "manual",
        signal: AbortSignal.timeout(12_000),
      });
      if (response.status < 300 || response.status >= 400) break;
      const location = response.headers.get("location");
      if (!location) throw new Error("Redirect missing location");
      currentUrl = new URL(location, currentUrl).toString();
      response = null;
    }
    if (response == null) throw new Error("Too many redirects");
    const contentType = response.headers.get("content-type")?.split(";")[0] ?? "";
    if (!["text/html", "application/xhtml+xml"].includes(contentType)) {
      throw new Error(`Unsupported content type: ${contentType || "unknown"}`);
    }
    const declaredLength = Number(response.headers.get("content-length") ?? 0);
    if (declaredLength > 2_000_000) throw new Error("Response too large");
    const html = await response.text();
    if (html.length > 2_000_000) throw new Error("Response too large");

    return new Response(
      JSON.stringify({
        success: true,
        html,
        status_code: response.status,
        final_url: currentUrl,
        content_length: html.length,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : "Unknown error during scraping";

    return new Response(
      JSON.stringify({
        success: false,
        error: message,
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
