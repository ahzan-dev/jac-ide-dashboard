# Register the metric endpoint IN-PROCESS in the gateway (plain server import, not sv import).
# Without this the scale layer auto-detects metrics_sv as a separate microservice.
import from metrics_sv { metric, metrics_batch, run_adhoc, verify_session }
import from billing_sv { billing_summary }

cl import ".styles.global.css";
cl import from ".components.Gate" { Gate }
cl import from ".components.PublicReport" { PublicReport }

cl {
    # /report/<token> is the public shared-report view (read-only, outside the
    # auth Gate); everything else is the authenticated dashboard.
    def:pub app() -> JsxElement {
        p = str(window.location.pathname);
        if p.startswith("/report/") {
            return <PublicReport />;
        }
        return <Gate />;
    }
}
