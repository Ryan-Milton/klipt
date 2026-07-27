import { afterEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  auth: vi.fn(),
  issueTestLicense: vi.fn(),
}));

vi.mock("@/server/auth", () => ({ auth: mocks.auth }));
vi.mock("@/server/admin-licenses", () => ({ issueTestLicense: mocks.issueTestLicense }));

import { POST } from "./route";

function request(email: string, origin = "https://sandbox.klipt.dev") {
  const body = new FormData();
  body.set("email", email);
  return new Request("https://sandbox.klipt.dev/api/admin/licenses", {
    method: "POST",
    headers: { origin },
    body,
  });
}

afterEach(() => {
  vi.restoreAllMocks();
  vi.clearAllMocks();
});

describe("admin test license issuance", () => {
  it("rejects cross-origin requests before authentication", async () => {
    const response = await POST(request("tester@example.com", "https://example.com"));

    expect(response.status).toBe(403);
    expect(mocks.auth).not.toHaveBeenCalled();
  });

  it("requires the configured GitHub admin", async () => {
    mocks.auth.mockResolvedValue(null);

    const response = await POST(request("tester@example.com"));

    expect(response.status).toBe(401);
    expect(mocks.issueTestLicense).not.toHaveBeenCalled();
  });

  it("rejects invalid email input", async () => {
    mocks.auth.mockResolvedValue({ user: { githubId: "42124719" } });

    const response = await POST(request("not-an-email"));

    expect(response.status).toBe(303);
    expect(response.headers.get("location")).toBe(
      "https://sandbox.klipt.dev/admin?result=Enter%20a%20valid%20email",
    );
    expect(mocks.issueTestLicense).not.toHaveBeenCalled();
  });

  it("normalizes email and issues for the authenticated admin", async () => {
    mocks.auth.mockResolvedValue({ user: { githubId: "42124719" } });
    mocks.issueTestLicense.mockResolvedValue({ customerId: "customer", licenseId: "license" });

    const response = await POST(request("Tester@Example.COM"));

    expect(mocks.issueTestLicense).toHaveBeenCalledWith("tester@example.com", "42124719");
    expect(response.status).toBe(303);
    expect(response.headers.get("location")).toBe(
      "https://sandbox.klipt.dev/admin?result=Test%20license%20sent",
    );
  });

  it("returns a recoverable admin result when issuance fails", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    mocks.auth.mockResolvedValue({ user: { githubId: "42124719" } });
    mocks.issueTestLicense.mockRejectedValue(
      new Error("No current release artifact is configured"),
    );

    const response = await POST(request("tester@example.com"));

    expect(response.status).toBe(303);
    expect(response.headers.get("location")).toBe(
      "https://sandbox.klipt.dev/admin?result=No%20current%20release%20artifact%20is%20configured",
    );
  });
});
