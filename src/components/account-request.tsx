"use client";

import { useState, type FormEvent } from "react";

export function AccountRequest() {
  const [message, setMessage] = useState("");

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const response = await fetch("/api/account/request", {
      method: "POST",
      body: new FormData(event.currentTarget),
    });
    const payload = (await response.json()) as { message: string };
    setMessage(payload.message);
  }

  return (
    <form className="email-form" onSubmit={submit}>
      <label htmlFor="account-email">Purchase email</label>
      <div>
        <input id="account-email" name="email" type="email" autoComplete="email" required />
        <button className="button button-ink" type="submit">
          Email my link
        </button>
      </div>
      {message && <p role="status">{message}</p>}
    </form>
  );
}
