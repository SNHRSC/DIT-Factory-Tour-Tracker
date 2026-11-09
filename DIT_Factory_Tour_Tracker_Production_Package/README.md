# DIT Factory Tour Tracker — Deployment Package

## Included
- `index.html` — responsive web app with DIT satellite image, site overview image, leader GPS capture, group checkpoints, session/group setup, Supabase Auth (email magic link), database persistence, and Realtime subscriptions.
- `supabase-schema.sql` — starter database schema, indexes, RLS policies, and Realtime publication setup.

## Architecture
Tour Leader mobile browser (GPS) → Supabase Auth → `group_locations` (upsert latest group location) → Supabase Realtime → HR Monitor browser.
Checkpoint check-ins are written to `checkpoint_events`. The app groups people under one Tour Leader device; it does not track each employee's personal phone.

## Deploy
1. Create a Supabase project.
2. In SQL Editor, run `supabase-schema.sql`.
3. In Authentication → URL Configuration, add the final web app URL to Site URL / Redirect URLs.
4. Enable Email provider. Configure company-approved email delivery.
5. Add `index.html` to an HTTPS static host (company web server, Cloudflare Pages, Netlify, or GitHub Pages if approved).
6. Open the app, enter Supabase Project URL and Publishable/anon key, save, then sign in with an approved company email.
7. Create a Session. The creator is inserted as `admin` by the app. Create a group and start GPS from the assigned Tour Leader device.
8. For HR Monitor users, an admin must add their Auth user UUID to `session_members` with role `monitor`. For another Tour Leader, add role `leader`; the group must be created with that leader's user UUID. The current UI's basic create-group flow assigns the currently signed-in user as leader, so assigning a different leader should be done through an approved admin workflow.
9. HR Monitor signs in, pastes Session UUID, opens Session, and selects a Group. Realtime updates are shown for the selected group.

## Important production tasks before rollout
- Replace the sample checkpoint image positions with surveyed/approved checkpoint coordinates. The current marker positions are illustrative.
- Calibrate satellite image using 3 surveyed GPS/image control points. Validate with additional independent points; a 3-point affine fit is not proof of accuracy.
- Implement server-side admin/member provisioning and role management. Do not grant broad access to all employees.
- Add retention policy, audit logging, incident response, and company privacy notice/employee consent.
- Test GPS in the actual factory. Browser GPS may be unavailable/poor indoors and background tabs may throttle updates.
- Add server-side validation, rate limiting, monitoring, backup, and production domain/TLS.
- Review RLS policies with IT/security. Do not use Supabase `service_role` key in frontend.
- If the user needs continuous background tracking while the phone is locked, build a managed native mobile app; a browser tab cannot guarantee this.

## HOCO E91 / Apple Find My
HOCO E91 is treated as a separate accessory used through Apple's Find My experience. Apple Find My does not provide a public third-party API for this web app to ingest live accessory coordinates. It is not used as a location source or geofence sensor here.

## Data and accuracy
The app stores one latest GPS record per group in `group_locations` (upsert every ~5 seconds) and checkpoint events in `checkpoint_events`. GPS accuracy depends on handset, permissions, sky view, building structure and device power settings. It is not a worker safety or emergency location system.

## Local demo
The map and UI can be previewed without Supabase, but authentication, shared live updates, and persistent storage require a configured Supabase project. Serve over HTTPS for geolocation.
