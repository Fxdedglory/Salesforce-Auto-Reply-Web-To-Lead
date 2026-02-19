# CRM Analytics Project Guide

## Project: Salesforce Lead Funnel Analytics + MoM, Rolling Window & Pace Metrics

---

# 1. Project Overview

## Objective

Design a full analytics layer on top of the Salesforce CRM workflow to measure:

* Lead generation performance
* Qualification efficiency
* Conversion funnel metrics
* Month-over-Month (MoM) growth
* Rolling window analytics (30/60/90 days)
* Pace and projected performance

This project complements the CRM Workflow Project and transforms it into a data-driven portfolio system.

---

# 2. Analytics Architecture (Aligned With Your Data Engineering Goals)

## Internal Analytics (Phase 1)

```
Salesforce Objects (Lead, Contact, Account)
        ↓
Salesforce Reports
        ↓
Salesforce Dashboards (KPI Layer)
```

## Advanced Analytics (Phase 2 - Optional)

```
Salesforce API Export
        ↓
Data Warehouse (Snowflake / PostgreSQL)
        ↓
Power BI / Python / dbt Models
```

This aligns strongly with your ETL + Data Science portfolio direction.

---

# 3. Key Datasets to Track

## Core Objects

| Object      | Analytics Use                  |
| ----------- | ------------------------------ |
| Lead        | Funnel entry + source tracking |
| Contact     | Qualified person analytics     |
| Account     | Company-level metrics          |
| Opportunity | Revenue pipeline metrics       |

---

# 4. Core KPI Framework (Executive Metrics)

## Top Funnel Metrics

* Total Leads Created
* Leads per Day / Week / Month
* Lead Source Distribution (Web, Form, API)

## Qualification Metrics

* Qualified Leads
* Qualification Rate = Qualified / Total Leads
* Time to Qualification

## Conversion Metrics

* Lead → Contact Conversion Rate
* Lead → Account Creation Rate
* Lead → Opportunity Rate

---

# 5. Month-over-Month (MoM) Analysis Design

## Report Configuration

Report Type: Leads

Grouping Strategy:

* Group Rows by: Created Date
* Date Granularity: Calendar Month

Primary Metrics:

* Row Count (Total Leads)
* Qualified Leads Count
* Converted Leads Count

MoM Growth Formula (Custom Field):

```
(Current Month Leads - Previous Month Leads) / Previous Month Leads
```

---

# 6. Rolling Window Analytics (Critical for Real-World CRM)

## Rolling Windows to Implement

* Last 7 Days
* Last 30 Days
* Last 90 Days
* Year-to-Date (YTD)

Dynamic Filter Examples:

* Created Date = LAST 30 DAYS
* Created Date = THIS MONTH
* Created Date = LAST 90 DAYS

Use Cases:

* Recruiter pipeline velocity
* Campaign performance tracking
* Lead trend momentum

---

# 7. Pace Metrics (Advanced KPI for Portfolio Differentiation)

## Definition

Pace = Projected performance based on current trend within a time period.

Example Formula:

```
Pace = (Current Leads / Days Elapsed) * Total Days in Month
```

Salesforce Custom Formula Metric:

* Use TODAY() function
* Create Custom Summary Formula in Report Builder

Business Value:

* Forecast monthly lead volume
* Detect underperformance early
* Executive forecasting dashboard

---

# 8. Funnel Visualization Model

## Recommended Dashboard Components

* Lead Volume Trend (Line Chart)
* Qualification Rate (Gauge)
* Conversion Funnel (Stacked Bar)
* Leads by Source (Pie Chart)
* Rolling 30-Day Leads (Metric Card)
* Pace Projection (Custom Metric)

---

# 9. Analytics for Your Specific Workflow (DocuSign + Qualification Stamp)

## Custom Tracking Metrics

* DocuSign Approval Rate
* Leads Approved via Stamp
* Average Time: Lead → Approval
* Form Completion Rate (Company vs Contact)
* Workflow Completion Rate

Suggested Formula:

```
Workflow Completion Rate = Completed Workflows / Qualified Leads
```

---

# 10. Data Quality & Validation Analytics

Track:

* Missing Required Fields
* Duplicate Leads
* Invalid Emails
* Incomplete Forms

This adds a Data Governance layer (very valuable for analytics roles).

---

# 11. Dashboard Strategy (Portfolio-Grade Setup)

## Dashboard 1 — Executive CRM Overview

* Total Leads (YTD)
* MoM Growth
* Conversion Rate
* Qualified Leads Trend

## Dashboard 2 — Operational Sales Dashboard

* Pending Form Tasks
* Qualified Leads Awaiting Conversion
* Contact & Account Creation Metrics

## Dashboard 3 — Data Science Extension (Optional)

* Lead Trend Forecasting
* Seasonality Detection
* Rolling Averages

---

# 12. Milestones & Phases

## Phase 1 — Reporting Foundation

* [ ] Create Lead Reports
* [ ] Create Qualification Reports
* [ ] Create Conversion Reports

## Phase 2 — KPI & Formula Metrics

* [ ] MoM Growth Formula
* [ ] Pace Metric
* [ ] Conversion Rate Calculations

## Phase 3 — Dashboard Layer

* [ ] Executive Dashboard
* [ ] Sales Operations Dashboard
* [ ] Funnel Visualization

## Phase 4 — Advanced Analytics (Optional)

* [ ] Salesforce Data Export API
* [ ] Warehouse Modeling (Star Schema)
* [ ] Power BI Integration

---

# 13. Portfolio & Career Impact

This analytics project demonstrates:

* CRM Analytics Engineering
* KPI Design & Metric Modeling
* Time-Series Analysis (MoM, Rolling Windows)
* BI Dashboard Development
* Integration with Enterprise CRM Systems

Combined with your CRM Workflow Project, this becomes a full:

> End-to-End CRM + Analytics System (Capture → Automate → Analyze)

This is extremely strong for:

* Data Analyst
* Analytics Engineer
* Salesforce Developer
* Data Engineer (CRM pipelines)
