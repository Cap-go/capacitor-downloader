# @capgo/capacitor-accelerometer
 <a href="https://capgo.app/"><img src='https://raw.githubusercontent.com/Cap-go/capgo/main/assets/capgo_banner.png' alt='Capgo - Instant updates for capacitor'/></a>

<div align="center">
  <h2><a href="https://capgo.app/?ref=plugin"> ➡️ Get Instant updates for your App with Capgo</a></h2>
  <h2><a href="https://capgo.app/consulting/?ref=plugin"> Missing a feature? We’ll build the plugin for you 💪</a></h2>
</div>


Access raw accelerometer measurements across iOS, Android, and the Web.

WIP: the plugin is not yet ready for production

## Documentation

The most complete doc is available here: https://capgo.app/docs/plugins/accelerometer/

## Install

```bash
npm install @capgo/capacitor-accelerometer
npx cap sync
```

## API

<docgen-index>

* [`getMeasurement()`](#getmeasurement)
* [`isAvailable()`](#isavailable)
* [`startMeasurementUpdates()`](#startmeasurementupdates)
* [`stopMeasurementUpdates()`](#stopmeasurementupdates)
* [`checkPermissions()`](#checkpermissions)
* [`requestPermissions()`](#requestpermissions)
* [`addListener('measurement', ...)`](#addlistenermeasurement-)
* [`removeAllListeners()`](#removealllisteners)
* [Interfaces](#interfaces)
* [Type Aliases](#type-aliases)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

Capacitor plugin contract for working with the device accelerometer.

### getMeasurement()

```typescript
getMeasurement() => Promise<GetMeasurementResult>
```

Get the most recent accelerometer sample that was recorded by the native layer.

**Returns:** <code>Promise&lt;<a href="#measurement">Measurement</a>&gt;</code>

**Since:** 1.0.0

--------------------


### isAvailable()

```typescript
isAvailable() => Promise<IsAvailableResult>
```

Check if the current device includes an accelerometer sensor.

**Returns:** <code>Promise&lt;<a href="#isavailableresult">IsAvailableResult</a>&gt;</code>

**Since:** 1.0.0

--------------------


### startMeasurementUpdates()

```typescript
startMeasurementUpdates() => Promise<void>
```

Begin streaming accelerometer updates to the JavaScript layer.

Call {@link addListener} with the `measurement` event to receive the updates.

**Since:** 1.0.0

--------------------


### stopMeasurementUpdates()

```typescript
stopMeasurementUpdates() => Promise<void>
```

Stop streaming accelerometer updates started via {@link startMeasurementUpdates}.

**Since:** 1.0.0

--------------------


### checkPermissions()

```typescript
checkPermissions() => Promise<PermissionStatus>
```

Return the current permission state for accessing motion data.

On platforms without explicit permissions this resolves to `granted`.

**Returns:** <code>Promise&lt;<a href="#permissionstatus">PermissionStatus</a>&gt;</code>

**Since:** 1.0.0

--------------------


### requestPermissions()

```typescript
requestPermissions() => Promise<PermissionStatus>
```

Request permission to access motion data if supported by the platform.

**Returns:** <code>Promise&lt;<a href="#permissionstatus">PermissionStatus</a>&gt;</code>

**Since:** 1.0.0

--------------------


### addListener('measurement', ...)

```typescript
addListener(eventName: 'measurement', listenerFunc: (event: MeasurementEvent) => void) => Promise<PluginListenerHandle>
```

Listen for measurement updates.

| Param              | Type                                                                    | Description                                |
| ------------------ | ----------------------------------------------------------------------- | ------------------------------------------ |
| **`eventName`**    | <code>'measurement'</code>                                              | Only the `measurement` event is supported. |
| **`listenerFunc`** | <code>(event: <a href="#measurement">Measurement</a>) =&gt; void</code> | Callback invoked with each measurement.    |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

**Since:** 1.0.0

--------------------


### removeAllListeners()

```typescript
removeAllListeners() => Promise<void>
```

Remove all listeners that have been registered on the plugin.

**Since:** 1.0.0

--------------------


### Interfaces


#### Measurement

The x, y and z axis acceleration values reported by the device motion sensors.

| Prop    | Type                | Description                            | Since |
| ------- | ------------------- | -------------------------------------- | ----- |
| **`x`** | <code>number</code> | The acceleration on the x-axis in G's. | 1.0.0 |
| **`y`** | <code>number</code> | The acceleration on the y-axis in G's. | 1.0.0 |
| **`z`** | <code>number</code> | The acceleration on the z-axis in G's. | 1.0.0 |


#### IsAvailableResult

Result returned by {@link CapacitorAccelerometerPlugin.isAvailable}.

| Prop              | Type                 | Description                                                 | Since |
| ----------------- | -------------------- | ----------------------------------------------------------- | ----- |
| **`isAvailable`** | <code>boolean</code> | Whether an accelerometer sensor is available on the device. | 1.0.0 |


#### PermissionStatus

Permission information returned by {@link CapacitorAccelerometerPlugin.checkPermissions}
and {@link CapacitorAccelerometerPlugin.requestPermissions}.

| Prop                | Type                                                                                  | Description                                                             | Since |
| ------------------- | ------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- | ----- |
| **`accelerometer`** | <code><a href="#accelerometerpermissionstate">AccelerometerPermissionState</a></code> | The permission state for accessing motion data on the current platform. | 1.0.0 |


#### PluginListenerHandle

| Prop         | Type                                      |
| ------------ | ----------------------------------------- |
| **`remove`** | <code>() =&gt; Promise&lt;void&gt;</code> |


### Type Aliases


#### GetMeasurementResult

Alias for the most recent measurement.

<code><a href="#measurement">Measurement</a></code>


#### AccelerometerPermissionState

Permission state union including `limited` for platforms that can throttle motion access.

<code><a href="#permissionstate">PermissionState</a> | 'limited'</code>


#### PermissionState

<code>'prompt' | 'prompt-with-rationale' | 'granted' | 'denied'</code>


#### MeasurementEvent

Event payload emitted when {@link CapacitorAccelerometerPlugin.startMeasurementUpdates}
is active.

<code><a href="#measurement">Measurement</a></code>

</docgen-api>

### Credit

This plugin was inspired from: https://github.com/kesha-antonov/react-native-background-downloader
