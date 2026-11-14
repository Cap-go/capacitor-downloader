/**
 * Type-level compatibility checks for DownloadOptions and DownloadBatchOptions.
 * Compiled via `bun run check:types`.
 */
import type { DownloadBatchOptions, DownloadOptions } from './definitions';

type SingleWithoutId = Omit<DownloadOptions, 'id'>;

const readDestination = (options: DownloadOptions): string => options.destination;
const readUrl = (options: SingleWithoutId): string => options.url;

interface ClientDownloadPayload extends DownloadOptions {
  clientTag?: string;
}

interface BatchOnlyPayload extends DownloadBatchOptions {
  clientTag?: string;
}

const singleOk: ClientDownloadPayload = {
  id: 'single',
  url: 'https://example.com/file',
  destination: 'pack/file.zip',
};

const batchOk: BatchOnlyPayload = {
  id: 'batch',
  files: [{ url: 'https://example.com/a.zip', destination: 'a.zip' }],
};

const mixedBatchShape = {
  id: 'bad',
  // @ts-expect-error batch options cannot include top-level url
  url: 'https://example.com/x',
  files: [{ url: 'https://example.com/a.zip', destination: 'a.zip' }],
} satisfies DownloadBatchOptions;

void mixedBatchShape;
void readDestination;
void readUrl;
void singleOk;
void batchOk;
