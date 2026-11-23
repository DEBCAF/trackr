This is a [Next.js](https://nextjs.org) project bootstrapped with [`create-next-app`](https://nextjs.org/docs/app/api-reference/cli/create-next-app).

## Getting Started

First, run the development server:

```bash
npm run dev
# or
yarn dev
# or
pnpm dev
# or
bun dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

You can start editing the page by modifying `app/page.tsx`. The page auto-updates as you edit the file.

This project uses [`next/font`](https://nextjs.org/docs/app/building-your-application/optimizing/fonts) to automatically optimize and load [Geist](https://vercel.com/font), a new font family for Vercel.

## Learn More

To learn more about Next.js, take a look at the following resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.

You can check out [the Next.js GitHub repository](https://github.com/vercel/next.js) - your feedback and contributions are welcome!

## Deploy on Vercel

The easiest way to deploy your Next.js app is to use the [Vercel Platform](https://vercel.com/new?utm_medium=default-template&filter=next.js&utm_source=create-next-app&utm_campaign=create-next-app-readme) from the creators of Next.js.

Check out our [Next.js deployment documentation](https://nextjs.org/docs/app/building-your-application/deploying) for more details.

## Supabase account setup

1. Create your account in Supabase Authentication with email and password.
2. Run `supabase/transactions_rls.sql` in the Supabase SQL Editor.
3. Backfill existing transactions by replacing the email in the commented query in that SQL file with your account email, then run the query.
4. Run `supabase/allowance.sql` in the Supabase SQL Editor.
5. Set `TRACKR_OWNER_ID` (your Auth user UUID, from Supabase Authentication → Users) and `CRON_SECRET` in `.env.local` and in Vercel.

The dashboard and transaction API require a signed-in account. Row-level security limits transaction access to that account.

### Daily allowance

The `ensure_allowance` database function adds £40 (`allowance_settings.daily_amount`) to the balance for every UK calendar day that doesn't have one yet, up to today. It runs whenever the dashboard loads, and the Vercel cron (`/api/cron/allowance`, just after midnight UTC) calls it as a backup. A unique index allows only one allowance per day, so repeated runs never double-add, and a missed day is caught up on the next run.

The **Pause daily allowance** button on the dashboard stops new days being added. **Resume** starts again from today; paused days are never back-filled. "Today's Allowance Remaining" is today's allowance minus today's expenses. Manual top-ups change the balance but not this number.
