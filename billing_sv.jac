"""Billing / margin — joins metered inference cost (PostHog) with Stripe MRR.

Degrades honestly: with no STRIPE_SECRET_KEY the endpoint returns {available:false, reason},
so the Cost page shows an honest '—' instead of a fabricated margin. Add the key to activate.
"""

import os;
import stripe;

glob STRIPE_KEY: str = os.environ.get("STRIPE_SECRET_KEY", "");


def:priv billing_summary() -> dict {
    if not STRIPE_KEY {
        return {"available": False, "reason": "STRIPE_SECRET_KEY not set on the server.", "mrr": None, "active_subs": 0};
    }
    try {
        stripe.api_key = STRIPE_KEY;
        subs = stripe.Subscription.list(status="active", limit=100);
        mrr = 0.0;
        count = 0;
        for s in subs.auto_paging_iter() {
            count = count + 1;
            items = s["items"]["data"];
            for it in items {
                price = it["price"];
                amt = ((price["unit_amount"] or 0) as float) / 100.0;
                interval = str(price["recurring"]["interval"]);
                qty = (it["quantity"] or 1) as float;
                monthly = amt;
                if interval == "year" {
                    monthly = amt / 12.0;
                }
                mrr = mrr + monthly * qty;
            }
        }
        return {"available": True, "reason": "", "mrr": round(mrr, 2), "active_subs": count};
    } except Exception as e {
        return {"available": False, "reason": str(e)[:140], "mrr": None, "active_subs": 0};
    }
}
