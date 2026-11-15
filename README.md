# QuickPoll 1.3

A small poll tool for Canvas, written as a hackweek project to learn LTI 1.3. An instructor or a TA creates polls in a course. Everyone in the course votes once per poll. A person sees the counts after voting.

This app started as a copy of QuickPoll 1.1 (`quickpoll_1p1`, an LTI 1.1 tool). It runs side by side with that app in the same local Canvas, with its own database. It does not use Canvas's 1.1-to-1.3 migration feature.

Status: the 1.3 launch works end to end in the local Canvas (login, token check, roles, polls, votes). The 1.1 code is still in this repo until step F in `zscratchpads/TODO.md`.

## Read this first

- `zscratchpads/quickpoll-1p3-walkthrough.html`: how a 1.3 tool works, what Canvas needs, how the two talk, and which file does what.
- `zscratchpads/lti-1p1-vs-1p3.html`: the differences between a 1.1 tool and a 1.3 tool, with pictures.
- `zscratchpads/TODO.md`: progress, install steps, known gaps.

## Requirements

- Docker, and inst-cli with the local Canvas running (`canvas-web.inseng.test`)
- Traefik from inst-cli. The app answers on http://quickpoll-1p3.inseng.test

Ruby, Rails 8, and Postgres 17 run inside the containers. Nothing installs on your machine.

## Run it

```
docker compose up -d
docker compose exec -T web bin/rails db:prepare
curl http://quickpoll-1p3.inseng.test/lti/tool_config
```

Tests:

```
docker compose exec -T web bash -lc 'bundle exec rspec'
```

Logs (works from any directory):

```
docker logs quickpoll_1p3-web-1 --tail 100 2>&1 | grep "\[lti launch\]"
```

A running server loads gems once. After a Gemfile change, run `docker compose restart web`.

## Install in the local Canvas

The full steps, with the traps, are in `zscratchpads/TODO.md`. In short:

1. `docker compose exec -T web bin/rails lti:platform`
2. In Canvas, make an LTI developer key from `http://quickpoll-1p3.inseng.test/lti/tool_config`, with the redirect URI `http://quickpoll-1p3.inseng.test/lti/launch`. Turn it on.
3. On the app page, copy the client id (the long number), set Availability to Available, and find the deployment id.
4. `docker compose exec -T web bin/rails lti:register CLIENT_ID=<client id> DEPLOYMENT_ID=<deployment id>`
5. Click QuickPoll 1.3 in the course navigation.

## Configuration

- `PUBLIC_BASE_URL` (set in `docker-compose.yml`): the URL Canvas and the browser use to reach the app. Every URL the app hands out is built from it.
- `INST_DOMAIN` (default `inseng.test`): used by the `lti:platform` task to find the local Canvas.

## Data and privacy

A launch carries names, a user id (`sub`), and sometimes an email. That is student and teacher data, so FERPA applies (and GDPR for EU users). Use synthetic users in a test course. Keep real launches out of docs, fixtures, and logs. The app never logs a token.
