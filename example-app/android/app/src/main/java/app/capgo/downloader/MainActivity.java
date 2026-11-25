package app.capgo.downloader;

import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.os.Bundle;

import com.getcapacitor.Bridge;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    private static final String E2E_JS_FLAG = "window.__capgoMaestroIsE2E=true;";

    private String buildMaestroPublishJs(Intent intent) {
        StringBuilder js = new StringBuilder(E2E_JS_FLAG);
        if (intent == null) {
            return js.toString();
        }
        String serverPort = intent.getStringExtra("maestroServerPort");
        if (serverPort != null && !serverPort.isEmpty()) {
            js.append("window.__capgoMaestroServerPort=").append(serverPort).append(";");
        }
        return js.toString();
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        publishE2EIntentExtra();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        publishE2EIntentExtra();
    }

    @Override
    public void onStart() {
        super.onStart();
        publishE2EIntentExtra();
        publishDebugMaestroFlag();
    }

    private void publishE2EIntentExtra() {
        Intent intent = getIntent();
        if (intent == null || !intent.getBooleanExtra("isE2E", false)) {
            return;
        }

        Bridge bridge = getBridge();
        if (bridge == null) {
            return;
        }

        bridge.eval(buildMaestroPublishJs(intent), null);
    }

    private void publishDebugMaestroFlag() {
        if (!isDebuggableBuild()) {
            return;
        }
        Bridge bridge = getBridge();
        if (bridge == null) {
            return;
        }
        bridge.eval(buildMaestroPublishJs(getIntent()), null);
    }

    private boolean isDebuggableBuild() {
        return (getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    }
}