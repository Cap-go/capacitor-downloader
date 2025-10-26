# @capgo/capacitor-downloader
 <a href="https://capgo.app/"><img src='https://raw.githubusercontent.com/Cap-go/capgo/main/assets/capgo_banner.png' alt='Capgo - Instant updates for capacitor'/></a>

<div align="center">
  <h2><a href="https://capgo.app/?ref=plugin"> ➡️ Get Instant updates for your App with Capgo</a></h2>
  <h2><a href="https://capgo.app/consulting/?ref=plugin"> Missing a feature? We’ll build the plugin for you 💪</a></h2>
</div>


Download file in background or foreground

WIP: the plugin is not yet ready for production

## Documentation

The most complete doc is available here: https://capgo.app/docs/plugins/downloader/

## Install

```bash
npm install @capgo/capacitor-downloader
npx cap sync
```

## API

<docgen-index>

* [`download(...)`](#download)
* [`pause(...)`](#pause)
* [`resume(...)`](#resume)
* [`stop(...)`](#stop)
* [`checkStatus(...)`](#checkstatus)
* [`getFileInfo(...)`](#getfileinfo)
* [`addListener('downloadProgress', ...)`](#addlistenerdownloadprogress-)
* [`addListener('downloadCompleted', ...)`](#addlistenerdownloadcompleted-)
* [`addListener('downloadFailed', ...)`](#addlistenerdownloadfailed-)
* [`removeAllListeners()`](#removealllisteners)
* [`getPluginVersion()`](#getpluginversion)
* [Interfaces](#interfaces)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

Capacitor plugin for downloading files with background support.
Provides resumable downloads with progress tracking.

### download(...)

```typescript
download(options: DownloadOptions) => Promise<DownloadTask>
```

Start a new download task.

| Param         | Type                                                        | Description              |
| ------------- | ----------------------------------------------------------- | ------------------------ |
| **`options`** | <code><a href="#downloadoptions">DownloadOptions</a></code> | - Download configuration |

**Returns:** <code>Promise&lt;<a href="#downloadtask">DownloadTask</a>&gt;</code>

--------------------


### pause(...)

```typescript
pause(id: string) => Promise<void>
```

Pause an active download.
Download can be resumed later from the same position.

| Param    | Type                | Description                        |
| -------- | ------------------- | ---------------------------------- |
| **`id`** | <code>string</code> | - ID of the download task to pause |

--------------------


### resume(...)

```typescript
resume(id: string) => Promise<void>
```

Resume a paused download.
Continues from where it was paused.

| Param    | Type                | Description                         |
| -------- | ------------------- | ----------------------------------- |
| **`id`** | <code>string</code> | - ID of the download task to resume |

--------------------


### stop(...)

```typescript
stop(id: string) => Promise<void>
```

Stop and cancel a download permanently.
Downloaded data will be deleted.

| Param    | Type                | Description                       |
| -------- | ------------------- | --------------------------------- |
| **`id`** | <code>string</code> | - ID of the download task to stop |

--------------------


### checkStatus(...)

```typescript
checkStatus(id: string) => Promise<DownloadTask>
```

Check the current status of a download.

| Param    | Type                | Description                        |
| -------- | ------------------- | ---------------------------------- |
| **`id`** | <code>string</code> | - ID of the download task to check |

**Returns:** <code>Promise&lt;<a href="#downloadtask">DownloadTask</a>&gt;</code>

--------------------


### getFileInfo(...)

```typescript
getFileInfo(path: string) => Promise<{ size: number; type: string; }>
```

Get information about a downloaded file.

| Param      | Type                | Description                  |
| ---------- | ------------------- | ---------------------------- |
| **`path`** | <code>string</code> | - Local file path to inspect |

**Returns:** <code>Promise&lt;{ size: number; type: string; }&gt;</code>

--------------------


### addListener('downloadProgress', ...)

```typescript
addListener(eventName: 'downloadProgress', listenerFunc: (progress: { id: string; progress: number; }) => void) => Promise<PluginListenerHandle>
```

Listen for download progress updates.
Fired periodically as download progresses.

| Param              | Type                                                                  | Description                           |
| ------------------ | --------------------------------------------------------------------- | ------------------------------------- |
| **`eventName`**    | <code>'downloadProgress'</code>                                       | - Must be 'downloadProgress'          |
| **`listenerFunc`** | <code>(progress: { id: string; progress: number; }) =&gt; void</code> | - Callback receiving progress updates |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

--------------------


### addListener('downloadCompleted', ...)

```typescript
addListener(eventName: 'downloadCompleted', listenerFunc: (result: { id: string; }) => void) => Promise<PluginListenerHandle>
```

Listen for download completion.
Fired when a download finishes successfully.

| Param              | Type                                              | Description                                  |
| ------------------ | ------------------------------------------------- | -------------------------------------------- |
| **`eventName`**    | <code>'downloadCompleted'</code>                  | - Must be 'downloadCompleted'                |
| **`listenerFunc`** | <code>(result: { id: string; }) =&gt; void</code> | - Callback receiving completion notification |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

--------------------


### addListener('downloadFailed', ...)

```typescript
addListener(eventName: 'downloadFailed', listenerFunc: (error: { id: string; error: string; }) => void) => Promise<PluginListenerHandle>
```

Listen for download failures.
Fired when a download encounters an error.

| Param              | Type                                                            | Description                            |
| ------------------ | --------------------------------------------------------------- | -------------------------------------- |
| **`eventName`**    | <code>'downloadFailed'</code>                                   | - Must be 'downloadFailed'             |
| **`listenerFunc`** | <code>(error: { id: string; error: string; }) =&gt; void</code> | - Callback receiving error information |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

--------------------


### removeAllListeners()

```typescript
removeAllListeners() => Promise<void>
```

Remove all event listeners.
Cleanup method to prevent memory leaks.

--------------------


### getPluginVersion()

```typescript
getPluginVersion() => Promise<{ version: string; }>
```

Get the plugin version number.

**Returns:** <code>Promise&lt;{ version: string; }&gt;</code>

--------------------


### Interfaces


#### DownloadTask

Represents the current state and progress of a download task.

| Prop           | Type                                                                 | Description                             |
| -------------- | -------------------------------------------------------------------- | --------------------------------------- |
| **`id`**       | <code>string</code>                                                  | Unique identifier for the download task |
| **`progress`** | <code>number</code>                                                  | Download progress from 0 to 100         |
| **`state`**    | <code>'PENDING' \| 'RUNNING' \| 'PAUSED' \| 'DONE' \| 'ERROR'</code> | Current state of the download           |


#### DownloadOptions

Configuration options for starting a download.

| Prop              | Type                                     | Description                                      |
| ----------------- | ---------------------------------------- | ------------------------------------------------ |
| **`id`**          | <code>string</code>                      | Unique identifier for this download task         |
| **`url`**         | <code>string</code>                      | URL of the file to download                      |
| **`destination`** | <code>string</code>                      | Local file path where the download will be saved |
| **`headers`**     | <code>{ [key: string]: string; }</code>  | Optional HTTP headers to include in the request  |
| **`network`**     | <code>'cellular' \| 'wifi-only'</code>   | Network type requirement for download            |
| **`priority`**    | <code>'high' \| 'normal' \| 'low'</code> | Download priority level                          |


#### PluginListenerHandle

| Prop         | Type                                      |
| ------------ | ----------------------------------------- |
| **`remove`** | <code>() =&gt; Promise&lt;void&gt;</code> |

</docgen-api>

### Credit

This plugin was inspired from: https://github.com/kesha-antonov/react-native-background-downloader
