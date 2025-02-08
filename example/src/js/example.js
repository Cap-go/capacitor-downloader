import { CapacitorDownloader } from '@capgo&#x2F;capacitor-downloader';

window.testEcho = () => {
    const inputValue = document.getElementById("echoInput").value;
    CapacitorDownloader.echo({ value: inputValue })
}
