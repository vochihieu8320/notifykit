# NotifyKit

Ruby gem gửi thông báo (Zalo trước, sau đó SMS/Email) cho developer Việt Nam.

## Naming (đã chốt)
- Brand: NotifyKit · gem: `notify_kit` · module: `NotifyKit` · OA Zalo: NotifyKit.
- Gem cũ `notifykit` (2014, bỏ dở) đã tồn tại trên RubyGems — README phải ghi rõ không liên quan.

## Scope (đã chốt)
- Core: idempotency/dedup, retry an toàn, transactional outbox, adapter dùng hạ tầng của dev.
- Provider: Zalo (OA tin tư vấn + ZBS/ZNS template) trước; mock Zalo server cho test/demo.
- SDK không phụ thuộc DB cụ thể. Core thuần Ruby; durable mode qua StorageAdapter
  (MemoryStorage cho test/direct, ActiveRecordStorage dùng DB sẵn có của app).
  Postgres chỉ là DB dùng cho dummy app/test/demo, không phải dependency của gem.
- Ngoài scope hiện tại: bulk 100k, webhooks đầy đủ, dashboard, Node.

## Skills & docs (đọc trước khi code)
- `.claude/skills/rails-conventions` — controller/service/concern/ErrorHandler rules.
- `.claude/skills/ruby-sdk-design` — layering, provider contract, checklist thêm provider.
- `.claude/skills/rspec-style` — spec layout, conformance shared examples.
- `docs/architecture.md` — kiến trúc gem, Zalo là 1 trong nhiều provider.

## Stack
- Tương thích Rails 7 (railtie + ActiveRecord/ActiveJob adapter là optional, core không require Rails).
<!-- TODO: Ruby version -->
- Test: RSpec.
<!-- TODO: linter (RuboCop / Standard) -->
<!-- TODO: queue adapter mặc định: Postgres-only / Sidekiq / ActiveJob / SolidQueue -->

## Commands
Ruby is NOT installed on the host — everything runs in Docker (ruby:3.3 + postgres:16).
- `docker compose run --rm app bundle install` — first time / after Gemfile change
- `bin/dev bundle exec rspec` — full suite (unit + conformance + integration on Postgres)
- `bin/dev bundle exec rubocop` — lint (must be clean)
- `docker compose run --rm -w /app/spec/dummy app bundle exec bin/rails g notify_kit:install` — generator
- Mock Zalo server: `spec/support/mock_servers/zalo.rb` (started automatically by specs)

## Conventions
### Ruby/Rails (bắt buộc)
- Controller chỉ nhận request, gọi service, render response. Không chứa business logic.
- Error handling: một module chung nằm ngoài `app/` (vd `lib/notifykit/errors` + concern `ErrorHandler`
  dùng `rescue_from`), controller chỉ include, không tự rescue lẻ tẻ.
- Business logic nằm trong service objects (`app/services`, một public method `call`, trả result object).
- Model gọn: tách logic bằng concerns (`app/models/concerns`), chỉ giữ association/validation/scope.
- Test bằng RSpec (không dùng Minitest). Service và adapter đều phải có spec.
- Trong gem (không có controller): áp dụng cùng tinh thần — public API mỏng (`NotifyKit::Client`)
  → service/use-case objects → adapters; lỗi dùng chung hệ `NotifyKit::Error`.
  Dummy/demo Rails app tuân thủ đầy đủ các quy tắc trên.

### Git
- Git: commit bằng identity cá nhân của maintainer (repo-local config).
<!-- TODO: branch/commit convention, ngôn ngữ commit message, ngôn ngữ code comment & docs -->

## Zalo
- Secrets chỉ nằm trong `.env` / `zalo_token.json` (đã gitignore). Không bao giờ commit.
- Refresh token dùng một lần → mọi refresh phải đi qua TokenStore có lock.

## Cách làm việc với Claude
<!-- TODO: làm theo từng bước nhỏ & hỏi trước? tự viết test trước (TDD)? mức độ tự quyết? -->
