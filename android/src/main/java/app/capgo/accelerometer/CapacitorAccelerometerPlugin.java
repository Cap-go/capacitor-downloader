package app.capgo.accelerometer;

import android.content.Context;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import androidx.annotation.Nullable;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

@CapacitorPlugin(name = "CapacitorAccelerometer")
public class CapacitorAccelerometerPlugin extends Plugin implements SensorEventListener {

    private static final String PERMISSION_GRANTED = "granted";
    private static final String PERMISSION_DENIED = "denied";

    @Nullable
    private SensorManager sensorManager;

    @Nullable
    private Sensor accelerometer;

    private final JSObject lastMeasurement = new JSObject();

    private boolean updatesActive = false;

    @Override
    public void load() {
        Context context = getContext();
        sensorManager = (SensorManager) context.getSystemService(Context.SENSOR_SERVICE);
        if (sensorManager != null) {
            accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER);
        }
        lastMeasurement.put("x", 0);
        lastMeasurement.put("y", 0);
        lastMeasurement.put("z", 0);
    }

    @PluginMethod
    public void getMeasurement(PluginCall call) {
        if (accelerometer == null) {
            call.reject("Accelerometer sensor not available on this device.");
            return;
        }
        call.resolve(snapshotMeasurement());
    }

    @PluginMethod
    public void isAvailable(PluginCall call) {
        JSObject result = new JSObject();
        result.put("isAvailable", accelerometer != null);
        call.resolve(result);
    }

    @PluginMethod
    public void startMeasurementUpdates(PluginCall call) {
        if (accelerometer == null) {
            call.reject("Accelerometer sensor not available on this device.");
            return;
        }
        if (updatesActive) {
            call.resolve();
            return;
        }
        if (sensorManager != null && sensorManager.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_GAME)) {
            updatesActive = true;
            call.resolve();
        } else {
            call.reject("Failed to register accelerometer listener.");
        }
    }

    @PluginMethod
    public void stopMeasurementUpdates(PluginCall call) {
        if (sensorManager != null && updatesActive) {
            sensorManager.unregisterListener(this);
            updatesActive = false;
        }
        call.resolve();
    }

    @PluginMethod
    public void checkPermissions(PluginCall call) {
        JSObject result = new JSObject();
        result.put("accelerometer", accelerometer != null ? PERMISSION_GRANTED : PERMISSION_DENIED);
        call.resolve(result);
    }

    @PluginMethod
    public void requestPermissions(PluginCall call) {
        // No explicit runtime permission is required for accelerometer access.
        checkPermissions(call);
    }

    @PluginMethod
    public void removeAllListeners(PluginCall call) {
        super.removeAllListeners(call);
    }

    @Override
    public void handleOnPause() {
        if (sensorManager != null && updatesActive) {
            sensorManager.unregisterListener(this);
        }
        super.handleOnPause();
    }

    @Override
    public void handleOnResume() {
        super.handleOnResume();
        if (updatesActive && sensorManager != null && accelerometer != null) {
            sensorManager.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_GAME);
        }
    }

    @Override
    public void handleOnDestroy() {
        if (sensorManager != null) {
            sensorManager.unregisterListener(this);
        }
        super.handleOnDestroy();
    }

    @Override
    public void onSensorChanged(SensorEvent event) {
        if (event.sensor.getType() != Sensor.TYPE_ACCELEROMETER) {
            return;
        }
        double x = event.values[0] / SensorManager.GRAVITY_EARTH;
        double y = event.values[1] / SensorManager.GRAVITY_EARTH;
        double z = event.values[2] / SensorManager.GRAVITY_EARTH;

        lastMeasurement.put("x", x);
        lastMeasurement.put("y", y);
        lastMeasurement.put("z", z);

        JSObject payload = new JSObject();
        payload.put("x", x);
        payload.put("y", y);
        payload.put("z", z);
        notifyListeners("measurement", payload);
    }

    @Override
    public void onAccuracyChanged(Sensor sensor, int accuracy) {
        // No-op
    }

    private JSObject snapshotMeasurement() {
        JSObject copy = new JSObject();
        copy.put("x", lastMeasurement.optDouble("x", 0));
        copy.put("y", lastMeasurement.optDouble("y", 0));
        copy.put("z", lastMeasurement.optDouble("z", 0));
        return copy;
    }
}
