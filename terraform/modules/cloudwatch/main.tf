# CloudWatch Module - Monitoring and Alerting

# Log Groups for Microservices
resource "aws_cloudwatch_log_group" "microservices" {
  for_each = var.microservices

  name              = "/eks/${var.environment}/${each.key}"
  retention_in_days = each.value.log_retention_days

  kms_key_id = var.kms_key_id

  tags = merge(var.tags, {
    Service = each.key
  })
}

# Application Log Groups
resource "aws_cloudwatch_log_group" "applications" {
  for_each = var.applications

  name              = "/app/${var.environment}/${each.key}"
  retention_in_days = each.value.log_retention_days

  kms_key_id = var.kms_key_id

  tags = merge(var.tags, {
    Application = each.key
  })
}

# Container Insights Log Group
resource "aws_cloudwatch_log_group" "container_insights" {
  name              = "/aws/containerinsights/${var.cluster_name}/performance"
  retention_in_days = var.container_insights_retention

  kms_key_id = var.kms_key_id

  tags = var.tags
}

# Metric Alarms - CPU
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  for_each = var.microservices

  alarm_name          = "${var.environment}-${each.key}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "cpu_utilization"
  namespace           = "AWS/EKS"
  period              = 300
  statistic           = "Average"
  threshold           = each.value.cpu_threshold
  alarm_description   = "CPU utilization is high for ${each.key}"

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = each.key
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = var.tags
}

# Metric Alarms - Memory
resource "aws_cloudwatch_metric_alarm" "high_memory" {
  for_each = var.microservices

  alarm_name          = "${var.environment}-${each.key}-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "memory_utilization"
  namespace           = "AWS/EKS"
  period              = 300
  statistic           = "Average"
  threshold           = each.value.memory_threshold
  alarm_description   = "Memory utilization is high for ${each.key}"

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = each.key
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = var.tags
}

# Metric Alarms - Error Rate
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  for_each = var.applications

  alarm_name          = "${var.environment}-${each.key}-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = each.value.error_threshold
  alarm_description   = "Error rate is high for ${each.key}"

  metric_query {
    id          = "error_rate"
    expression  = "(errors / total) * 100"
    label       = "Error Rate"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      metric_name = "http_5xx_errors"
      namespace   = "Application/${each.key}"
      period      = 300
      stat        = "Sum"
    }
  }

  metric_query {
    id = "total"
    metric {
      metric_name = "http_requests_total"
      namespace   = "Application/${each.key}"
      period      = 300
      stat        = "Sum"
    }
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = var.tags
}

# Metric Alarms - Latency
resource "aws_cloudwatch_metric_alarm" "high_latency" {
  for_each = var.applications

  alarm_name          = "${var.environment}-${each.key}-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "http_request_duration_seconds"
  namespace           = "Application/${each.key}"
  period              = 300
  extended_statistic  = "p99"
  threshold           = each.value.latency_threshold
  alarm_description   = "P99 latency is high for ${each.key}"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = var.tags
}

# SNS Topic for Alarms
resource "aws_sns_topic" "alarms" {
  name = "${var.environment}-alarms"

  kms_master_key_id = var.kms_key_id

  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.alert_emails)

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_sns_topic_subscription" "pagerduty" {
  count = var.pagerduty_integration_key != "" ? 1 : 0

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "https"
  endpoint  = "https://events.pagerduty.com/integration/${var.pagerduty_integration_key}/enqueue"
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.environment}-microservices"

  dashboard_body = jsonencode({
    widgets = concat(
      [
        {
          type   = "metric"
          x      = 0
          y      = 0
          width  = 12
          height = 6
          properties = {
            title  = "Cluster CPU Utilization"
            region = var.aws_region
            metrics = [
              ["AWS/EKS", "cluster_failed_node_count", "ClusterName", var.cluster_name, { color = "#d62728", stat = "Average" }],
              [".", "cluster_node_count", ".", ".", { color = "#2ca02c", stat = "Average" }]
            ]
            period = 300
            yAxis = {
              left = {
                min = 0
              }
            }
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 0
          width  = 12
          height = 6
          properties = {
            title  = "Pod Status"
            region = var.aws_region
            metrics = [
              ["ContainerInsights", "pod_number_of_container_restarts", "ClusterName", var.cluster_name, { color = "#ff7f0e", stat = "Sum" }],
              [".", "pod_status_ready", ".", ".", { color = "#2ca02c", stat = "Average" }],
              [".", "pod_status_failed", ".", ".", { color = "#d62728", stat = "Average" }]
            ]
            period = 300
          }
        }
      ],
      [
        for i, service in keys(var.microservices) : {
          type   = "metric"
          x      = (i % 2) * 12
          y      = 6 + floor(i / 2) * 6
          width  = 12
          height = 6
          properties = {
            title  = "${service} - CPU & Memory"
            region = var.aws_region
            metrics = [
              ["AWS/EKS", "pod_cpu_utilization", "ClusterName", var.cluster_name, "ServiceName", service, { color = "#1f77b4", stat = "Average" }],
              [".", "pod_memory_utilization", ".", ".", ".", ".", { color = "#ff7f0e", stat = "Average" }]
            ]
            period = 300
            annotations = {
              horizontal = [
                {
                  value = var.microservices[service].cpu_threshold
                  label = "CPU Threshold"
                  color = "#d62728"
                },
                {
                  value = var.microservices[service].memory_threshold
                  label = "Memory Threshold"
                  color = "#9467bd"
                }
              ]
            }
          }
        }
      ]
    )
  })
}

# Log Metric Filters
resource "aws_cloudwatch_log_metric_filter" "errors" {
  for_each = var.applications

  name           = "${var.environment}-${each.key}-errors"
  pattern        = "{ $.level = \"ERROR\" || $.level = \"FATAL\" }"
  log_group_name = aws_cloudwatch_log_group.applications[each.key].name

  metric_transformation {
    name          = "${each.key}_errors"
    namespace     = "Application/${each.key}"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

# CloudWatch Logs Insights Query Definitions
resource "aws_cloudwatch_query_definition" "error_analysis" {
  for_each = var.applications

  name = "${var.environment}/${each.key}/Error Analysis"

  log_group_names = [aws_cloudwatch_log_group.applications[each.key].name]

  query_string = <<-EOF
    fields @timestamp, @message, level, message, stack_trace
    | filter level in ["ERROR", "FATAL"]
    | sort @timestamp desc
    | limit 100
  EOF
}

resource "aws_cloudwatch_query_definition" "performance_analysis" {
  for_each = var.applications

  name = "${var.environment}/${each.key}/Performance Analysis"

  log_group_names = [aws_cloudwatch_log_group.applications[each.key].name]

  query_string = <<-EOF
    fields @timestamp, @message, duration_ms, path, method
    | filter ispresent(duration_ms)
    | stats avg(duration_ms) as avg_duration, max(duration_ms) as max_duration, percentile(duration_ms, 99) as p99 by bin(5m)
    | sort avg_duration desc
  EOF
}
