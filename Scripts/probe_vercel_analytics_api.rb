#!/usr/bin/env ruby

require "io/console"
require "json"
require "net/http"
require "time"
require "uri"

API_BASE_URL = "https://api.vercel.com"
OUTPUT_PATH = ".build/vercel-api-probe.json"
SAFE_HEADER_NAMES = %w[
  retry-after
  x-ratelimit-limit
  x-ratelimit-remaining
  x-ratelimit-reset
  x-vercel-id
].freeze
SAFE_METRIC_KEYS = %w[pageviews visitors].freeze
SAFE_DIMENSION_KEYS = %w[referrerHostname requestPath].freeze

def prompt_for_token
  token = ENV.fetch("VERCEL_TOKEN", "").strip
  return token unless token.empty?

  abort "Set VERCEL_TOKEN or run the probe from an interactive terminal." unless $stdin.tty?

  $stderr.print "Vercel access token (input is hidden): "
  token = $stdin.noecho(&:gets).to_s.strip
  $stderr.puts
  token
end

def response_payload(response, body)
  {
    "status" => response.code.to_i,
    "headers" => SAFE_HEADER_NAMES.to_h { |name| [name, response[name]] }.compact,
    "body" => body,
  }
end

def request(path, query, token)
  uri = URI.join(API_BASE_URL, path)
  uri.query = URI.encode_www_form(query)

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Accept"] = "application/json"
    http.request(request)
  end

  body = JSON.parse(response.body)
  response_payload(response, body)
rescue JSON::ParserError
  response_payload(response, {})
rescue StandardError => error
  {
    "status" => 0,
    "headers" => {},
    "body" => {},
    "networkError" => error.class.name,
  }
end

def request_summary(response)
  body = response.fetch("body")
  error = body["error"]

  {
    "status" => response.fetch("status"),
    "headers" => response.fetch("headers"),
    "errorCode" => error.is_a?(Hash) ? error["code"] : nil,
    "networkError" => response["networkError"],
  }.compact
end

def successful?(response)
  response.fetch("status").between?(200, 299)
end

def paginated_values(path, key, query, token)
  values = []
  cursors = []
  cursor = nil

  loop do
    page_query = query.merge("limit" => 100)
    page_query["until"] = cursor if cursor
    response = request(path, page_query, token)
    break [values, cursors, request_summary(response)] unless successful?(response)

    body = response.fetch("body")
    values.concat(Array(body[key]))
    next_cursor = body.dig("pagination", "next")
    break [values, cursors, request_summary(response)] if next_cursor.nil? || cursors.include?(next_cursor)

    cursors << next_cursor
    cursor = next_cursor
  end
end

def scopes_for(token, record)
  teams, team_cursors, teams_response = paginated_values("/v2/teams", "teams", {}, token)
  record["teams"] = {
    "response" => teams_response,
    "paginationCursorCount" => team_cursors.count,
  }

  scopes = [{ "kind" => "personal", "query" => {} }]
  teams.each do |team|
    next unless team["id"]

    scopes << {
      "kind" => "team",
      "query" => { "teamId" => team.fetch("id") },
    }
  end
  scopes
end

def projects_for(scopes, token, record)
  projects = []
  record["projectDiscovery"] = []

  scopes.each do |scope|
    values, cursors, response = paginated_values("/v9/projects", "projects", scope.fetch("query"), token)
    record.fetch("projectDiscovery") << {
      "scopeKind" => scope.fetch("kind"),
      "response" => response,
      "paginationCursorCount" => cursors.count,
      "projectCount" => values.count,
    }

    values.each do |project|
      next unless project["id"] && project["name"]

      projects << project.slice("id", "name").merge("scope" => scope)
    end
  end
  projects
end

def select_project(projects)
  abort "No accessible projects were returned by the public API." if projects.empty?

  $stderr.puts "Choose a project to query. This list is only shown locally and is not written to disk."
  projects.each_with_index do |project, index|
    $stderr.puts format("%3d. %s (%s)", index + 1, project.fetch("name"), project.dig("scope", "kind"))
  end

  loop do
    $stderr.print "Project number: "
    selection = Integer($stdin.gets.to_s, exception: false)
    return projects.fetch(selection - 1) if selection && selection.between?(1, projects.count)

    $stderr.puts "Enter a number from 1 to #{projects.count}."
  end
end

def range_queries(project)
  now = Time.now.utc
  query_base = project.dig("scope", "query").merge("projectId" => project.fetch("id"))

  [
    ["last24Hours", now - 86_400, now, "hour"],
    ["last7Days", now - (7 * 86_400), now, "day"],
    ["last30Days", now - (30 * 86_400), now, "day"],
  ].to_h do |name, since, end_time, granularity|
    [
      name,
      query_base.merge(
        "since" => since.iso8601,
        "until" => end_time.iso8601,
        "by" => granularity,
      ),
    ]
  end
end

def analytics_summary(response)
  body = response.fetch("body")
  rows = body["data"].is_a?(Array) ? body.fetch("data") : []
  count_data = body["data"].is_a?(Hash) ? body.fetch("data") : {}
  returned_query = body["query"].is_a?(Hash) ? body.fetch("query") : {}
  series_metric_keys = rows.select { |row| row.is_a?(Hash) }.flat_map(&:keys).uniq & SAFE_METRIC_KEYS

  request_summary(response).merge(
    "metricKeys" => count_data.keys & SAFE_METRIC_KEYS,
    "timeSeriesRowCount" => rows.count,
    "timeSeriesMetricKeys" => series_metric_keys,
    "returnedQuery" => returned_query.slice("since", "until", "groupBy", "filter"),
  )
end

def breakdown_summary(response, dimension)
  body = response.fetch("body")
  rows = body["data"].is_a?(Array) ? body.fetch("data") : []
  returned_query = body["query"].is_a?(Hash) ? body.fetch("query") : {}
  row_keys = rows.select { |row| row.is_a?(Hash) }.flat_map(&:keys).uniq

  request_summary(response).merge(
    "metricKeys" => row_keys & SAFE_METRIC_KEYS,
    "dimensionKeyPresent" => row_keys.include?(dimension),
    "returnedQuery" => returned_query.slice("since", "until", "groupBy", "filter", "limit"),
  )
end

def query_analytics(project, token)
  range_queries(project).to_h do |name, query|
    count = request("/v1/query/web-analytics/visits/count", query.reject { |key| key == "by" }, token)
    aggregate = request("/v1/query/web-analytics/visits/aggregate", query, token)
    production = request(
      "/v1/query/web-analytics/visits/count",
      query.reject { |key| key == "by" }.merge("filter" => "environment eq 'production'"),
      token,
    )

    [
      name,
      {
        "count" => analytics_summary(count),
        "aggregate" => analytics_summary(aggregate),
        "explicitProductionMatchesDefault" =>
          successful?(count) &&
          successful?(production) &&
          count.fetch("body")["data"] == production.fetch("body")["data"],
      },
    ]
  end
end

def query_breakdowns(project, token)
  query = range_queries(project).fetch("last7Days")

  SAFE_DIMENSION_KEYS.to_h do |dimension|
    breakdown_query = query.merge(
      "by" => dimension,
      "limit" => 5,
      "filter" => "environment eq 'production'",
    )
    response = request("/v1/query/web-analytics/visits/aggregate", breakdown_query, token)

    [dimension, breakdown_summary(response, dimension)]
  end
end

def write_record(record)
  directory = File.dirname(OUTPUT_PATH)
  Dir.mkdir(directory) unless Dir.exist?(directory)
  File.write(OUTPUT_PATH, JSON.pretty_generate(record) + "\n")
  $stderr.puts "Sanitized contract record written to #{OUTPUT_PATH}."
end

token = prompt_for_token
abort "A Vercel access token is required." if token.empty?

record = {
  "schemaVersion" => 3,
  "generatedAt" => Time.now.utc.iso8601,
  "apiBaseURL" => API_BASE_URL,
  "privateDashboardEndpointsUsed" => false,
  "documentation" => [
    "https://vercel.com/docs/analytics/web-analytics-api",
    "https://vercel.com/docs/rest-api/web-analytics/aggregates-page-views",
    "https://vercel.com/docs/rest-api/web-analytics/counts-page-views",
  ],
  "knownLimitations" => {
    "bounceRate" => "Not exposed by the documented visits endpoints.",
    "analyticsEnabled" => "Not exposed by public project discovery; query results determine availability.",
    "rateLimitAndTransientErrors" => "Not intentionally induced; safe response headers are captured when present.",
  },
}

validation = request("/v2/teams", { "limit" => 1 }, token)
record["tokenValidation"] = request_summary(validation).merge("endpoint" => "/v2/teams")
record["currentUserProbe"] = request_summary(request("/v2/user", {}, token))
unless successful?(validation)
  record["invalidTokenProbe"] = request_summary(request("/v2/teams", { "limit" => 1 }, "invalid"))
  write_record(record)
  abort "Token validation failed. The sanitized result was recorded."
end

record["invalidTokenProbe"] = request_summary(request("/v2/teams", { "limit" => 1 }, "invalid"))
scopes = scopes_for(token, record)
projects = projects_for(scopes, token, record)
project = select_project(projects)
record["selectedProject"] = { "scopeKind" => project.dig("scope", "kind") }
record["analytics"] = query_analytics(project, token)
record["breakdowns"] = query_breakdowns(project, token)
write_record(record)
