#!/usr/bin/env python3
"""
Batch Card Benefits Extraction Script
=====================================
Runs the full extraction pipeline for all credit cards in the catalog:
1. Fetches card catalog from Supabase
2. For each card with a card_url, scrapes via Edge Function proxy
3. Sends HTML to Gemini API for structured benefit extraction
4. Writes extracted benefits to card_benefits_staging table

Usage: python3 batch_extract_benefits.py [--limit N] [--bank BANK_NAME]
"""

import json
import re
import sys
import time
import urllib.request
import urllib.error

# ─── Configuration ───
with open('dart_defines.json') as f:
    config = json.load(f)

SUPABASE_URL = config['SUPABASE_URL']
SUPABASE_KEY = config['SUPABASE_ANON_KEY']
GEMINI_KEYS = [config['GEMINI_API_KEY'], config.get('GEMINI_API_KEY_2', '')]
GEMINI_KEYS = [k for k in GEMINI_KEYS if k]  # Filter empty

EDGE_FUNCTION_URL = f"{SUPABASE_URL}/functions/v1/scrape-card"

# Rate limiting - Groq TPM is 6000, each call uses ~3000-4000 tokens
GEMINI_DELAY_SECONDS = 4  # Wait between Gemini API calls
SCRAPE_DELAY_SECONDS = 1  # Wait between scrape requests
GROQ_DELAY_SECONDS = 15   # Wait between Groq calls (6000 TPM limit)

current_key_idx = 0

def supabase_request(method, path, data=None, params=None):
    """Make a Supabase REST API request."""
    url = f"{SUPABASE_URL}/rest/v1/{path}"
    if params:
        from urllib.parse import quote
        url += '?' + '&'.join(f'{k}={quote(str(v), safe="*.,:")}' for k, v in params.items())

    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header('apikey', SUPABASE_KEY)
    req.add_header('Authorization', f'Bearer {SUPABASE_KEY}')
    req.add_header('Content-Type', 'application/json')
    if method == 'POST':
        req.add_header('Prefer', 'return=representation')

    resp = urllib.request.urlopen(req, timeout=30)
    return json.loads(resp.read())


def scrape_card_url(url):
    """Scrape card page HTML via Edge Function proxy."""
    body = json.dumps({'url': url}).encode()
    req = urllib.request.Request(EDGE_FUNCTION_URL, data=body)
    req.add_header('Content-Type', 'application/json')
    req.add_header('Authorization', f'Bearer {SUPABASE_KEY}')

    resp = urllib.request.urlopen(req, timeout=45)
    data = json.loads(resp.read())

    if data.get('success') and data.get('html'):
        return data['html']
    return None


def extract_benefit_text(html):
    """Extract benefit-related text from HTML."""
    # Remove script/style tags
    html = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL | re.IGNORECASE)
    html = re.sub(r'<style[^>]*>.*?</style>', '', html, flags=re.DOTALL | re.IGNORECASE)
    # Remove HTML tags
    text = re.sub(r'<[^>]+>', ' ', html)
    text = re.sub(r'\s+', ' ', text)

    keywords = [
        'benefit', 'reward', 'cashback', 'points', 'lounge', 'insurance',
        'dining', 'travel', 'fuel', 'shopping', 'entertainment', 'utility',
        'annual fee', 'joining fee', 'milestone', 'tier', 'accelerated',
        'complimentary', 'welcome', 'fee waiver', 'forex', 'emi', 'privilege',
        'feature', 'offer', 'discount', 'surcharge', 'earn', 'redeem',
        'interest', 'rate', 'waiver', 'concierge', 'priority pass'
    ]

    sentences = text.split('.')
    benefit_sentences = [
        s.strip() for s in sentences
        if any(kw in s.lower() for kw in keywords) and len(s.strip()) > 10
    ]

    return '. '.join(benefit_sentences[:80])[:6000]


def call_gemini(prompt, retry_count=0):
    """Call Gemini API with automatic key rotation, then fallback to Groq."""
    global current_key_idx

    # Try Gemini first
    key = GEMINI_KEYS[current_key_idx % len(GEMINI_KEYS)]

    body = json.dumps({
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "temperature": 0.1,
            "maxOutputTokens": 4096,
        }
    }).encode()

    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={key}"
    req = urllib.request.Request(url, data=body)
    req.add_header('Content-Type', 'application/json')

    try:
        resp = urllib.request.urlopen(req, timeout=60)
        result = json.loads(resp.read())
        text = result['candidates'][0]['content']['parts'][0]['text']
        return text
    except urllib.error.HTTPError as e:
        if e.code == 429 and retry_count < len(GEMINI_KEYS):
            current_key_idx += 1
            print(f"\n    ⚠️  Gemini rate limited on key {current_key_idx-1}, trying key {current_key_idx % len(GEMINI_KEYS)}...", end='')
            time.sleep(2)
            return call_gemini(prompt, retry_count + 1)
        elif e.code == 429:
            # All Gemini keys exhausted, fall back to Groq
            print(f"\n    🔄 All Gemini keys exhausted, falling back to Groq...", end='')
            return call_groq(prompt)
        raise


def call_groq(prompt, retry_count=0):
    """Fallback: Call Groq API via curl subprocess."""
    import subprocess, tempfile

    groq_key = config.get('GROQ_API_KEY', '')
    if not groq_key:
        raise Exception("No GROQ_API_KEY configured")

    # Write request body to temp file (avoids shell escaping issues)
    body = {
        "model": "llama-3.1-8b-instant",
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.1,
        "max_tokens": 4096
    }

    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump(body, f)
        temp_path = f.name

    try:
        result = subprocess.run(
            ['curl', '-s', '-X', 'POST', 'https://api.groq.com/openai/v1/chat/completions',
             '-H', 'Content-Type: application/json',
             '-H', f'Authorization: Bearer {groq_key}',
             '-d', f'@{temp_path}'],
            capture_output=True, text=True, timeout=60
        )

        data = json.loads(result.stdout)
        if 'choices' in data:
            return data['choices'][0]['message']['content']
        elif 'error' in data:
            error_msg = data['error'].get('message', 'unknown')
            # Check for rate limit with retry
            if 'rate limit' in error_msg.lower() and retry_count < 3:
                # Parse wait time from error message
                import re as _re
                wait_match = _re.search(r'try again in (\d+\.?\d*)s', error_msg)
                wait_time = float(wait_match.group(1)) + 1 if wait_match else 15
                print(f"\n    ⏳ Groq TPM limit, waiting {wait_time:.0f}s...", end='', flush=True)
                time.sleep(wait_time)
                return call_groq(prompt, retry_count + 1)
            raise Exception(f"Groq error: {error_msg}")
        else:
            raise Exception(f"Unexpected Groq response: {result.stdout[:200]}")
    finally:
        import os
        os.unlink(temp_path)


def extract_benefits_for_card(card_name, bank_name, html_content):
    """Use Gemini to extract structured benefits from HTML content."""
    benefit_text = extract_benefit_text(html_content)

    if len(benefit_text) < 50:
        return None

    prompt = f"""You are an expert Indian credit card analyst. Extract ALL benefits from this {bank_name} {card_name} credit card.

Return valid JSON with these EXACT fields:
{{
  "card_name": "{card_name}",
  "bank_name": "{bank_name}",
  "annual_fee": {{"first_year": null, "renewal": null, "waiver_conditions": null}},
  "benefits": [
    {{
      "category": "CASHBACK|REWARDS|DINING|TRAVEL|FUEL|SHOPPING|GROCERY|ENTERTAINMENT|UTILITY|INSURANCE|LOUNGE|MILESTONE|GENERAL",
      "description": "Detailed description",
      "value": 0,
      "value_type": "percentage|points_per_100|flat_amount|multiplier",
      "monthly_cap": null,
      "annual_cap": null,
      "merchants": null,
      "conditions": null
    }}
  ],
  "special_benefits": [
    {{"type": "text", "description": "text"}}
  ],
  "fees": {{
    "foreign_transaction_markup": null,
    "fuel_surcharge_waiver": null,
    "emi_conversion": null
  }}
}}

Include ALL benefits found - cashback rates, reward points, milestone rewards, lounge access, insurance, fuel surcharge waivers, etc.
Each benefit should be a separate entry in the "benefits" array.
Use null for unknown values, not "Not specified".

CARD PAGE CONTENT:
{benefit_text}"""

    response_text = call_gemini(prompt)

    # Parse JSON from response
    try:
        # Try direct parse
        data = json.loads(response_text)
        return data
    except json.JSONDecodeError:
        # Try extracting JSON from markdown code block
        match = re.search(r'```(?:json)?\s*(.*?)\s*```', response_text, re.DOTALL)
        if match:
            try:
                data = json.loads(match.group(1))
                return data
            except json.JSONDecodeError:
                pass
        return None


def save_to_staging(card_id, source_url, extracted_data):
    """Save extracted benefits to staging table."""
    try:
        result = supabase_request('POST', 'card_benefits_staging', {
            'card_id': card_id,
            'source_url': source_url or 'Official Bank Website',
            'extracted_data': extracted_data,
            'status': 'pending',
        })
        return result[0]['id'] if result else None
    except Exception as e:
        print(f"    ⚠️  Staging save failed: {e}")
        return None


def main():
    import argparse
    parser = argparse.ArgumentParser(description='Batch extract card benefits')
    parser.add_argument('--limit', type=int, default=5, help='Max cards to process')
    parser.add_argument('--bank', type=str, default=None, help='Filter by bank name')
    parser.add_argument('--card', type=str, default=None, help='Filter by card name (partial match)')
    parser.add_argument('--run-tag', type=str, default=None, help='Tag for this run (for comparison)')
    args = parser.parse_args()

    run_tag = args.run_tag or f'run-{int(time.time())}'

    # Fetch all cards with URLs
    params = {
        'select': 'id,bank,card_name,card_url',
        'card_url': 'not.is.null',
        'order': 'bank.asc,card_name.asc',
    }
    if args.bank:
        params['bank'] = f'ilike.*{args.bank}*'
    if args.card:
        params['card_name'] = f'ilike.*{args.card}*'

    cards = supabase_request('GET', 'card_catalog', params=params)

    total = len(cards)
    limit = min(args.limit, total)

    print(f"\n{'='*60}")
    print(f"  CARDCOMPASS BATCH BENEFIT EXTRACTION")
    print(f"  Total cards with URLs: {total}")
    print(f"  Processing: {limit} cards")
    print(f"  Gemini API keys: {len(GEMINI_KEYS)}")
    print(f"  Run tag: {run_tag}")
    print(f"{'='*60}\n")

    success_count = 0
    fail_count = 0
    skip_count = 0
    results = {}  # card_id -> extracted_data for comparison

    for i, card in enumerate(cards[:limit]):
        card_id = card['id']
        bank = card['bank']
        name = card['card_name']
        url = card['card_url']

        print(f"\n[{i+1}/{limit}] {bank} - {name}")
        print(f"  URL: {url}")

        # Step 1: Scrape
        try:
            print(f"  📥 Scraping...", end=' ', flush=True)
            html = scrape_card_url(url)
            if not html or len(html) < 500:
                print(f"SKIP (too short: {len(html or '')} chars)")
                skip_count += 1
                continue
            print(f"OK ({len(html):,} chars)")
        except Exception as e:
            print(f"FAIL: {e}")
            fail_count += 1
            continue

        time.sleep(SCRAPE_DELAY_SECONDS)

        # Step 2: Extract benefits via Gemini
        try:
            print(f"  🤖 Extracting benefits...", end=' ', flush=True)
            data = extract_benefits_for_card(name, bank, html)
            if not data:
                print("SKIP (no data extracted)")
                skip_count += 1
                continue

            benefits_count = len(data.get('benefits', []))
            special_count = len(data.get('special_benefits', []))
            print(f"OK ({benefits_count} benefits, {special_count} special)")
            results[card_id] = data
        except Exception as e:
            print(f"FAIL: {e}")
            fail_count += 1
            time.sleep(GROQ_DELAY_SECONDS)
            continue

        time.sleep(GROQ_DELAY_SECONDS)

        # Step 3: Save to staging
        try:
            print(f"  💾 Saving to staging...", end=' ', flush=True)
            staging_id = save_to_staging(card_id, url, data)
            if staging_id:
                print(f"OK (ID: {staging_id[:8]}...)")
                success_count += 1
            else:
                print("SKIP (save failed)")
                skip_count += 1
        except Exception as e:
            print(f"FAIL: {e}")
            fail_count += 1

    print(f"\n{'='*60}")
    print(f"  EXTRACTION COMPLETE")
    print(f"  ✅ Success: {success_count}")
    print(f"  ❌ Failed:  {fail_count}")
    print(f"  ⏭️  Skipped: {skip_count}")
    print(f"{'='*60}\n")

    # ─── Cross-validation against baseline ───
    import os, hashlib
    baseline_path = os.path.join(os.path.dirname(__file__), 'baseline_snapshot.json')
    if os.path.exists(baseline_path) and results:
        with open(baseline_path) as f:
            baseline = json.load(f)

        print(f"\n{'='*60}")
        print(f"  CROSS-VALIDATION vs BASELINE")
        print(f"{'='*60}\n")

        match_count = 0
        diff_count = 0
        new_count = 0

        for cid, new_data in results.items():
            benefits = new_data.get('benefits', [])
            special = new_data.get('special_benefits', [])
            new_benefit_count = len(benefits)
            new_special_count = len(special)
            desc_str = '|'.join(sorted(b.get('description','') for b in benefits))
            new_hash = hashlib.md5(desc_str.encode()).hexdigest()[:8]

            if cid in baseline:
                old = baseline[cid]
                old_bc = old['benefit_count']
                old_sc = old['special_count']
                old_hash = old['hash']

                count_match = abs(new_benefit_count - old_bc) <= 2  # Allow ±2 variation
                hash_match = new_hash == old_hash

                if count_match and hash_match:
                    match_count += 1
                elif count_match:
                    print(f"  ⚠️  {cid[:8]}: counts similar ({old_bc}→{new_benefit_count}) but descriptions differ")
                    diff_count += 1
                else:
                    print(f"  ❌ {cid[:8]}: benefit count changed ({old_bc}→{new_benefit_count}, special {old_sc}→{new_special_count})")
                    diff_count += 1
            else:
                new_count += 1

        total_compared = match_count + diff_count
        pct = (match_count / max(total_compared, 1)) * 100
        print(f"\n  ✅ Exact match: {match_count}")
        print(f"  ⚠️  Divergent:  {diff_count}")
        print(f"  🆕 New cards:   {new_count}")
        print(f"  📊 Consistency: {pct:.1f}%")
        print(f"{'='*60}\n")


if __name__ == '__main__':
    main()
