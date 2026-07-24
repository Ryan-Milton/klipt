import "server-only";

import NextAuth from "next-auth";
import GitHub from "next-auth/providers/github";

import { env } from "@/server/env";

export const { handlers, auth, signIn, signOut } = NextAuth({
  providers: [
    GitHub({
      clientId: process.env.AUTH_GITHUB_ID ?? "unconfigured",
      clientSecret: process.env.AUTH_GITHUB_SECRET ?? "unconfigured",
      authorization: { params: { scope: "read:user" } },
    }),
  ],
  session: { strategy: "jwt", maxAge: 8 * 60 * 60 },
  cookies: {
    sessionToken: {
      name: process.env.NODE_ENV === "production" ? "__Secure-klipt.admin" : "klipt.admin",
      options: {
        httpOnly: true,
        sameSite: "lax",
        path: "/",
        secure: process.env.NODE_ENV === "production",
      },
    },
  },
  callbacks: {
    signIn({ account }) {
      const config = env.auth();
      return (
        account?.provider === "github" && account.providerAccountId === config.ADMIN_GITHUB_USER_ID
      );
    },
    jwt({ token, account }) {
      if (account?.provider === "github") token.githubId = account.providerAccountId;
      return token;
    },
    session({ session, token }) {
      session.user.githubId = String(token.githubId ?? "");
      return session;
    },
  },
});
