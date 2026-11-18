# Wayside Nails: Walk-in Queue

A free website that runs the walk-in line.

- **Tech view** (`your-site.netlify.app`): read-only, live. Techs open it on their phones.
- **Front desk** (`your-site.netlify.app/manager.html`): password-protected. This is where the manager or receptionist runs the line.

Everything updates live on every screen. Total cost: **$0** (Supabase free plan plus Netlify free plan).

---

## How the line works

1. Every tech is in one of four states:
   - **Off**: not working today. This is the default each morning.
   - **Waiting**: has a numbered spot in the line.
   - **Requested**: keeps their spot, but is with a customer who asked for them.
   - **Busy**: working on a walk-in. They sit in the Busy area and have no spot.
2. **Walk-in:** tap the service. The customer goes to the **first Waiting tech from the top who can do that service**. Techs who are skipped keep their spot. The chosen tech moves to Busy.
3. **Done with a walk-in:** the tech goes to the **bottom** of the line.
4. **Requested:** tap **Requested** next to a tech and pick the service. They stay in their spot (and move up as others get customers), but they get no walk-ins.
5. **Done with a request:** the tech becomes Waiting again **in the same spot**, so they can take customers back to back.
6. **Adding a tech** (arriving, or back from a break) puts them at the **bottom**.
7. **Two services at the same time** (for example a pedicure and a manicure together): tap both services. Two techs are assigned.
8. **Undo** reverses the last line change. **Drag ☰** to reorder the line by hand.
9. Each new day the line empties by itself. History is kept for 30 days.

**Edge cases:**
- **Everyone who can do the service is busy:** you'll see "No one is free for X right now." Nothing changes.
- **Nobody on today can do the service:** you'll see "Nobody on the line today can do X."
- **Requesting a tech who is busy with a walk-in:** this is blocked with "Mark them done first."
- **Removing a tech who is with a customer:** the app asks first, then logs the job as finished.
- **Two people tapping at the same moment:** taps are handled one at a time, so nobody is double-assigned.

---

## Files

| File | What it is |
|---|---|
| `index.html` + `js/view.js` | Tech view (read-only) |
| `manager.html` + `js/manager.js` | Front desk screen (Line, Techs & Services, History) |
| `js/common.js` | Shared code (loading data, live updates) |
| `js/config.js` | **Your Supabase address and key. This is the only file you edit.** |
| `css/style.css` | Look and feel |
| `supabase/setup.sql` | Creates the database and all the line rules |
| `supabase/test_sample_day.sql` | Developer test. **Never run it on the real database.** |

---

## Setup guide (about 20 minutes, no coding)

You'll create two free accounts. Use the same GitHub login for both, so they can see your code.

### Step 1: Create the database (Supabase)

1. Go to **https://supabase.com** and click **Start your project**.
2. Click **Continue with GitHub** and approve.
3. Click **New project**.
   - **Name:** `wayside-queue`
   - **Database Password:** click **Generate a password**, then copy it somewhere safe. You won't need it for the app.
   - **Region:** pick the one closest to the salon.
   - Click **Create new project**. Wait about 2 minutes for it to finish setting up.

### Step 2: Load the queue rules into the database

1. In GitHub, open this repository, click the `supabase` folder, then click `setup.sql`.
2. Click the **copy** icon (two squares, top right of the file) to copy the whole file.
3. In Supabase, click **SQL Editor** in the left sidebar (the icon looks like `>_`).
4. Click **+ New query**, click in the big empty box, and paste (Ctrl+V on Windows, Cmd+V on Mac).
5. **Set the manager password:** scroll to the very bottom and find `CHANGE-THIS-PASSWORD`. Replace only those words with your own password, keeping the single quotes around it. For example: `'Wayside2026!'`
6. Click **Run** (bottom right). You should see **"Success. No rows returned."**
   - If Supabase shows a warning about "destructive operations", click **Run this query** to continue. The file doesn't delete any of your data.

### Step 3: Copy your two connection values

1. In Supabase, click the **Connect** button at the top of the page (or go to **Project Settings → API Keys**).
2. Copy the **Project URL**. It looks like `https://abcdefghijk.supabase.co`.
3. Copy the **Publishable key**. It starts with `sb_publishable_`. If you only see "Legacy API keys", copy the **anon public** key instead.

Both values are safe to put in a public website. The manager password is what protects changes.

### Step 4: Put the values into the website

1. On GitHub, open this repository, click the `js` folder, then click `config.js`.
2. Click the **pencil icon** (Edit this file).
3. Replace `PASTE-YOUR-PROJECT-URL-HERE` with your Project URL, and `PASTE-YOUR-PUBLISHABLE-KEY-HERE` with your key. Keep the quote marks.
4. Click **Commit changes…**, then **Commit changes** again.

### Optional: try it on your laptop before putting it online

You can skip Step 5 at first and run the site straight from your laptop. You still need Steps 1–4, because the line is stored in Supabase.

1. On GitHub, open this repository, click the green **Code** button, then **Download ZIP**.
2. Open your Downloads folder and unzip the file:
   - **Windows:** right-click it and choose **Extract All**.
   - **Mac:** double-click it.
3. Open the new `wayside-queue-main` folder.
4. Double-click `manager.html`. It opens in your web browser. Log in with your password.
5. Double-click `index.html` too. This is the tech view. Put the two windows side by side, tap a service in the manager window, and watch the tech view change by itself.

Only your laptop can see this copy. Phones need the online version from Step 5.

If you change `js/config.js` on GitHub later, download the ZIP again.

### Step 5: Put the website online (Netlify)

1. Go to **https://www.netlify.com** and click **Sign up**. Choose **Sign up with GitHub** and approve. If it asks about a plan, pick **Free**.
2. On your Netlify dashboard, click **Add new project** (it may say **Add new site**), then **Import an existing project**.
3. Click **GitHub**. If asked, approve Netlify's access to the `wayside-queue` repository.
4. Click `wayside-queue` in the list.
5. Leave every box empty or as it is. There is no build command and nothing to fill in. Click **Deploy**.
6. After about 30 seconds, your address appears at the top. It's something like `random-name-123.netlify.app`.
   - To get a nicer name, go to **Project configuration** (or **Site configuration**) → **Change project name**, and type something like `wayside-queue`. The address becomes `wayside-queue.netlify.app`.

From now on, every time code changes on GitHub, Netlify updates the website by itself within a minute.

### Step 6: Set up the devices

- **Front desk iPad or phone:** open `https://YOUR-ADDRESS.netlify.app/manager.html` in Safari and log in.
  - Tap the **Share** button (square with an arrow) and choose **Add to Home Screen**. It now opens like an app.
  - The device stays logged in until someone taps **Log out** (on the Techs & Services tab).
- **Each tech's phone:** send them `https://YOUR-ADDRESS.netlify.app` by text. They can **Add to Home Screen** too.

### Step 7: First-time setup in the app

1. On the front desk screen, open **Techs & Services**.
2. Type each tech's name and tap **Add**.
3. Under each tech, tap the services they can do. Services turn purple when they're on, and changes save right away.
4. Need a service that isn't listed (for example "Gel X")? Type it under **Services** and tap **Add**. Then turn it on for the right techs.

---

## Practice day (do this before using it for real)

Use the example from the planning:

1. In **Techs & Services**, add three practice techs:
   - **Maria**: Pedicure, Eyebrows
   - **Linh**: Pedicure, Full Set, Eyebrows
   - **Ana**: Full Set
2. On the **Line** tab, under **Not on the line**, tap **+ Maria**, then **+ Linh**, then **+ Ana**. The line should read 1 Maria, 2 Linh, 3 Ana.
3. Open the tech view on a second phone. It should show the same line.
4. Tap **Full Set**. The message should say "Full Set walk-in goes to Linh." Linh moves to Busy, and Maria stays #1. The phone updates within a second or two.
5. Tap **Done** next to Linh. Linh goes to the **bottom**: Maria, Ana, Linh.
6. Tap **Requested** next to Ana and pick **Full Set**. Ana turns orange but **keeps spot #2**.
7. Tap **Pedicure**. It goes to **Maria**. Ana moves up to #1, still orange.
8. Tap **Full Set**. Ana is skipped because she's requested, so it goes to Linh.
9. Tap **Full Set** again. You should see "No one is free for Full Set right now."
10. Tap **Waxing**. You should see "Nobody on the line today can do Waxing."
11. Tap **Done** next to Ana. She is available again **at #1**.
12. Tap **Undo**. Ana is back to Requested.
13. Drag the ☰ handle to move someone, then check that the phone shows the new order.
14. Open **History**. Every job is listed under each tech, with times.
15. When you're done, take the practice techs off the line. In **Techs & Services**, delete them. (Practice history disappears after 30 days.)

---

## Common problems

| Problem | Fix |
|---|---|
| Page says **"Almost there… not connected"** | Step 4 wasn't saved. Check `js/config.js` on GitHub, then wait 1 minute for Netlify to update. |
| **"Wrong password"** | Use the password you typed in Step 2. If you forgot it, open Supabase **SQL Editor** and run `update app_secret set password_hash = extensions.crypt('NewPassword', extensions.gen_salt('bf')) where id = 1;` |
| Top right shows **"Reconnecting…"** | The internet dropped, or the phone was asleep. It fixes itself, and the screen still refreshes every 30 seconds. Pull down to reload if needed. |
| **Everything stopped working after a week or more of no use** | Supabase pauses free projects after 7 days without activity. Log in to supabase.com, open the project, and click **Restore project**. Daily use keeps it awake. |
| Tapped the wrong thing | Tap **Undo** (it can go back many steps). |
| The line is in the wrong order | Drag the ☰ handles. |
| A tech is not getting a service | In **Techs & Services**, check that the service is purple (on) under that tech. |
| Times in History look wrong | Log out and back in on the front desk device. The salon's time zone is taken from that device when it logs in. |
| Old line still showing in the morning | Open the front desk screen. The line clears for the new day as soon as any screen opens. |

---

## Costs

- **Supabase free plan:** 500 MB database and live updates included. This app uses well under 1% of that.
- **Netlify free plan:** allows business use. This site is tiny, so it stays far below the free limits.
- **Optional:** your own domain (like `waysidequeue.com`) costs about $10–15 a year. Netlify can connect it under **Domain management**.
