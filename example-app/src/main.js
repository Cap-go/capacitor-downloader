import './style.css';
import { CapacitorAccelerometer } from '@capgo/capacitor-accelerometer';

const measurementLabel = document.getElementById('measurement');
const availabilityLabel = document.getElementById('availability');
const permissionLabel = document.getElementById('permission');
const startButton = document.getElementById('start-updates');
const stopButton = document.getElementById('stop-updates');
const singleReadButton = document.getElementById('read-once');

let measurementListener;

function formatMeasurement(measurement) {
  const x = measurement.x?.toFixed(3) ?? '0.000';
  const y = measurement.y?.toFixed(3) ?? '0.000';
  const z = measurement.z?.toFixed(3) ?? '0.000';
  return `x: ${x}g | y: ${y}g | z: ${z}g`;
}

async function refreshAvailability() {
  const { isAvailable } = await CapacitorAccelerometer.isAvailable();
  availabilityLabel.textContent = isAvailable ? 'Available' : 'Not available';
}

async function refreshPermission() {
  const { accelerometer } = await CapacitorAccelerometer.checkPermissions();
  permissionLabel.textContent = accelerometer;
}

async function ensurePermission() {
  const { accelerometer } = await CapacitorAccelerometer.requestPermissions();
  permissionLabel.textContent = accelerometer;
  if (accelerometer !== 'granted') {
    throw new Error(`Permission not granted: ${accelerometer}`);
  }
}

async function readOnce() {
  try {
    await ensurePermission();
    const measurement = await CapacitorAccelerometer.getMeasurement();
    measurementLabel.textContent = formatMeasurement(measurement);
  } catch (error) {
    measurementLabel.textContent = error.message;
  }
}

async function startUpdates() {
  try {
    await ensurePermission();
    if (!measurementListener) {
      measurementListener = await CapacitorAccelerometer.addListener('measurement', (event) => {
        measurementLabel.textContent = formatMeasurement(event);
      });
    }
    await CapacitorAccelerometer.startMeasurementUpdates();
    startButton.disabled = true;
    stopButton.disabled = false;
    singleReadButton.disabled = true;
  } catch (error) {
    measurementLabel.textContent = error.message;
  }
}

async function stopUpdates() {
  await CapacitorAccelerometer.stopMeasurementUpdates();
  if (measurementListener) {
    await measurementListener.remove();
    measurementListener = undefined;
  }
  startButton.disabled = false;
  stopButton.disabled = true;
  singleReadButton.disabled = false;
}

startButton.addEventListener('click', startUpdates);
stopButton.addEventListener('click', stopUpdates);
singleReadButton.addEventListener('click', readOnce);

refreshAvailability();
refreshPermission();
