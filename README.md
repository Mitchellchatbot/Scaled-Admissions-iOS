# Scaled Admissions for iOS

A SwiftUI app for the shared inbox: see every conversation, read the thread,
reply as yourself, and switch the AI on or off for a chat. Modelled on the
Care Assist app, styled by the web app's `docs/ui/README.md`.

The web app ([scaled-admissions](../scaled-admissions)) is expected next to
this folder; set `WEB_APP_DIR` if it lives somewhere else.

## Run it

```bash
brew install xcodegen          # once
cd ~/scaled-admissions-ios
./scripts/write-secrets.sh     # copies the public Supabase URL + key from the web app's .env.local
xcodegen                       # makes ScaledAdmissions.xcodeproj (not checked in)
open ScaledAdmissions.xcodeproj
```

Debug builds talk to `npm run dev` at `http://localhost:3000`. Release builds
use `NEXT_PUBLIC_APP_URL`.

## How it fits together

- **Reads** go straight to Supabase as the signed-in user, so the same RLS
  policies as the web inbox decide what shows (`Services/SupabaseService.swift`).
  Realtime on `messages` and `conversations` keeps the list and thread live.
- **Replies and the AI switch** need the workspace's encrypted Meta token, so
  they go through the web app: `POST /api/mobile/conversations/[id]/reply` and
  `/mode`, signed with the user's Supabase access token
  (`lib/supabase/bearer.ts`). Both share `lib/conversationControl.ts` with the
  web inbox.
- Sign-in is email and password, the same account as the web app.

After adding or moving Swift files, run `xcodegen` again.
