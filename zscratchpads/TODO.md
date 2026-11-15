# QuickPoll 1.3 - progress

This app started as a copy of the finished QuickPoll 1.1 tool (tag `v1.1-final` in `quickpoll_1p1`). It becomes a working LTI 1.3 tool. It does NOT use Canvas's 1.1-to-1.3 migration feature. Both apps stay installed in the local Canvas so you can compare them. The 1.3 app has its own database, so its users, polls, and votes are separate from 1.1.

Plan (the original 1.1-to-1.3 plan, with a status section on top): ../../zscratchpads/quickpoll_1p1_to_1p3_plan.md
Explainers in this folder: `quickpoll-1p3-walkthrough.html` (how this app works), `lti-1p1-vs-1p3.html` (1.1 against 1.3), `quickpoll-1p1-walkthrough.html` (the 1.1 code that still lives here until step F).

## Build steps

- [x] A: registration tables (`lti_platforms`, `lti_registrations`, `lti_deployments`). Each registration makes its own RSA key pair.
- [x] B: `GET /lti/jwks` (public keys) and `GET /lti/tool_config` (the JSON Canvas reads)
- [x] C: OIDC login, trip 1 (`/lti/login`, state and nonce saved in `lti_launch_states`)
- [x] D1: users and courses can belong to a platform (expand and contract migration)
- [x] D2: `Lti1p3::PlatformKeys` and `Lti1p3::LaunchVerifier` (17 refusal reasons)
- [x] D3: `LaunchController` accepts an `id_token`. `Lti1p3::LaunchRecords` saves the person and the course.
- [x] E: `Lti1p3::Roles`. A launch stores `can_create_polls`. The whole 1.3 flow has a request spec.
- [x] G: installed in the local Canvas, launched live as teacher, TA, and student. Real roles and claims captured (see "What a real Canvas launch sent").
- [ ] F: delete the 1.1 code (verifier, replay guard, consumers, `used_nonces`, XML config). Low priority: the 1.1 app lives in its own repo.

Commit status: steps A to E are committed. Two files from step G were still uncommitted on 2026-11-15: `app/services/lti1p3/platform_keys.rb` (the `require "net/http"` fix) and `lib/tasks/lti.rake`.

## Run it

- `docker compose up -d`, then open http://quickpoll-1p3.inseng.test/lti/tool_config
- Specs: `docker compose exec -T web bash -lc 'bundle exec rspec'` (326 examples at the end of step E)
- Logs: `docker logs quickpoll_1p3-web-1 --tail 100 2>&1 | grep "\[lti launch\]"` (works from any directory)
- A running `puma` loads gems once. After a Gemfile change, run `docker compose restart web`.

## Install in the local Canvas (about 10 minutes)

1. `docker compose exec -T web bin/rails lti:platform` makes the `LtiPlatform` row for the local Canvas. Safe to run twice.
2. In Canvas: Admin, Developer Keys, + Developer Key, LTI Key. Use Enter URL with `http://quickpoll-1p3.inseng.test/lti/tool_config` (or Paste JSON). Set Redirect URIs to `http://quickpoll-1p3.inseng.test/lti/launch`. Turn the key on. The app also shows under Admin, Apps, Manage, and the Developer Keys list may stay empty.
3. Open the app page (Apps, Manage, QuickPoll 1.3). Click **Copy Client ID**. That is the long number, like `10000000000011`. The short number in the URL (11) is wrong for `CLIENT_ID`.
4. On the same page, open **Availability and Exceptions** and set the account to **Available**. Canvas installs the tool as unavailable, and an unavailable tool does not show in course navigation.
5. Find the deployment id. It looks like `21:3ac312ee...`. A Canvas console query shows it: `ContextExternalTool.find(<id>).deployment_id`.
6. `docker compose exec -T web bin/rails lti:register CLIENT_ID=<long number> DEPLOYMENT_ID=<deployment id>`
7. Click QuickPoll 1.3 in the course navigation.

## What a real Canvas launch sent (checked 2026-11-14, local Canvas, synthetic users)

- Roles claim shapes match `Lti1p3::Roles`. Teacher: `institution/person#Instructor`, `membership#Instructor`, `system/person#User`. Student: `institution/person#Student`, `membership#Learner`, `system/person#User`.
- A TA sends BOTH `membership#Instructor` and `membership/Instructor#TeachingAssistant`. So a TA is also an instructor in 1.3.
- The `lti1p1` claim held only `user_id`. There was no `oauth_consumer_key` and no signature, because the 1.3 launch URL (`quickpoll-1p3.inseng.test`) does not match the 1.1 tool's URL. All three `user_id` values matched `lti_users.lti1p1_user_id` in the 1.1 database. So Canvas gives one person the same 1.1 id in both versions.
- Claims also include `lti11_legacy_user_id`, `lis`, `custom`, `eulaservice`, `tool_platform`, `launch_presentation`, and `https://www.instructure.com/placement`. The `email` claim appeared for the TA only.
- The launch URL carries `lti_storage_target=post_message_forwarding`. The tool ignores it today.

## Problems we hit going live (so the next person does not)

- `Net::HTTP` was not loaded. The specs stub the call, so only a live launch failed. Fixed with `require "net/http"` in `platform_keys.rb`.
- The running puma was older than the `json-jwt` entry in the Gemfile. `JSON::JWK` and `JSON::JWT` were missing until `docker compose restart web`.
- Canvas installs a new tool as unavailable (`Lti::ContextControl.available` is false). The tool shows nowhere until you turn it on under Availability and Exceptions.
- The short key id (11) is not the client id. The launch `aud` is the long number. A registration with the wrong value fails with `wrong_audience` or a 400 at login.

## Known gaps (not built)

- Login state is not tied to the browser. Anyone who knows an unused `state` and has a matching `id_token` could finish a launch. The `id_token` is signed by Canvas and holds the nonce, so this is hard, but a cookie or storage binding would close it. A cookie does not work in a third-party iframe. The `lti_storage_target` flow (post messages) is the real answer.
- `PlatformKeys` has no timeout and no cache. One slow Canvas stalls a launch. Cache by `kid` and refetch on a miss.
- The private key sits in Postgres as plain text. Use Rails `encrypts` or a secrets store before real use.
- Session cookie in an iframe. Works locally (same parent domain). In production it needs `same_site: :none` and `secure: true`, and Safari blocks it anyway.
- Two simultaneous votes from one person can raise `RecordNotUnique` (500). Rescue it and show "You already voted".
- Only `LtiResourceLinkRequest` launches work. A `LtiDeepLinkingRequest` is refused (`unsupported_message_type`).
- `/lti/jwks` publishes the public key of every registration. That is fine for one Canvas. Think again before you serve many platforms.
- No key rotation. A new key for a registration needs a second `kid` in the JWKS first.
- Governance: launch data holds names, `sub`, and sometimes email. That is student and teacher data (FERPA, and GDPR for EU users). Keep real launches out of docs, fixtures, and logs (a spec checks that the token is never logged). Security and Privacy review before any real account installs this.

## Stretch ideas (pick one at a time)

- Store `lti1p1_user_id` on the 1.3 person from the `lti1p1` claim (specs first). This is the base for a cutover.
- Cutover test: run the 1.3 app on the 1.1 hostname so Canvas finds the associated 1.1 tool. The claim then carries `oauth_consumer_key` and `oauth_consumer_key_sign`. Verify that signature with the stored secret.
- AGS grade passback (client credentials grant, line items, scores).
- NRPS (who has not voted), Deep Linking, Dynamic Registration.
