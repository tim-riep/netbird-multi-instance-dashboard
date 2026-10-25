import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  readRuntimeConfig,
  resetRuntimeConfig,
  RUNTIME_CONFIG_PATH,
} from "./config";

type Response = { status: number; body?: string; error?: Error };

const stubRequest = (response: Response) => {
  const requests: { method: string; url: string; async: boolean }[] = [];
  class FakeXMLHttpRequest {
    status = 0;
    responseText = "";
    open(method: string, url: string, async: boolean) {
      requests.push({ method, url, async });
    }
    send() {
      if (response.error) throw response.error;
      this.status = response.status;
      this.responseText = response.body ?? "";
    }
  }
  vi.stubGlobal("XMLHttpRequest", FakeXMLHttpRequest);
  return requests;
};

describe("readRuntimeConfig", () => {
  beforeEach(() => {
    resetRuntimeConfig();
    vi.spyOn(console, "error").mockImplementation(() => {});
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("loads the config for this hostname synchronously", () => {
    const requests = stubRequest({
      status: 200,
      body: '{"apiOrigin":"https://a.example.com"}',
    });

    expect(readRuntimeConfig()).toEqual({ apiOrigin: "https://a.example.com" });
    expect(requests).toEqual([
      { method: "GET", url: RUNTIME_CONFIG_PATH, async: false },
    ]);
  });

  it("requests the config only once per page", () => {
    const requests = stubRequest({ status: 200, body: "{}" });

    readRuntimeConfig();
    readRuntimeConfig();

    expect(requests).toHaveLength(1);
  });

  it.each([
    { desc: "not found", response: { status: 404 } },
    { desc: "invalid JSON", response: { status: 200, body: "$AUTH" } },
    { desc: "network error", response: { status: 0, error: new Error("x") } },
  ])("returns null when $desc", ({ response }) => {
    stubRequest(response);

    expect(readRuntimeConfig()).toBeNull();
  });
});
