import "next-auth";

declare module "next-auth" {
  interface User {
    githubId?: string;
  }

  interface Session {
    user: User & { githubId: string };
  }
}
