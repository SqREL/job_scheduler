FROM ruby:3.2-alpine

RUN apk add --no-cache git

WORKDIR /app
COPY Gemfile* ./
RUN bundle install

COPY . .

CMD ["ruby", "bin/scheduler", "-r", "${REPO_URL}"]
