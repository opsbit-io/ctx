import Foundation

// MARK: - FinOps & Cloud Cost Data Models

/// Time window for financial cost allocation and run-rate analysis.
public enum FinOpsTimeWindow: String, CaseIterable, Identifiable, Codable, Sendable {
    case h24 = "24h"
    case d7 = "7d"
    case d30 = "30d"
    case monthToDate = "month"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .h24: return "Last 24 Hours"
        case .d7: return "Last 7 Days"
        case .d30: return "Last 30 Days"
        case .monthToDate: return "Month to Date"
        }
    }

    public var shortName: String {
        switch self {
        case .h24: return "24 Hours"
        case .d7: return "7 Days"
        case .d30: return "30 Days"
        case .monthToDate: return "Month to Date"
        }
    }

    public var daysFactor: Double {
        switch self {
        case .h24: return 1.0
        case .d7: return 7.0
        case .d30: return 30.0
        case .monthToDate: return max(1.0, Double(Calendar.current.component(.day, from: Date())))
        }
    }

    public var monthlyMultiplier: Double {
        switch self {
        case .h24: return 30.0
        case .d7: return 30.0 / 7.0
        case .d30: return 1.0
        case .monthToDate: return 30.0 / max(1.0, Double(Calendar.current.component(.day, from: Date())))
        }
    }
}

/// Aggregation dimension for cost breakdown.
public enum FinOpsAggregation: String, CaseIterable, Identifiable, Codable, Sendable {
    case namespace = "namespace"
    case workload = "workload"
    case node = "node"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .namespace: return "Namespaces"
        case .workload: return "Workloads"
        case .node: return "Nodes"
        }
    }
}

/// Baseline hourly cloud rates for resource estimation when in-cluster agents (OpenCost/Kubecost)
/// are not yet installed.
public struct CloudPricingProfile: Codable, Equatable, Sendable {
    public var providerName: String
    public var cpuHourlyPerCore: Double      // e.g. $0.0316
    public var memoryHourlyPerGiB: Double    // e.g. $0.00423
    public var storageMonthlyPerGB: Double   // e.g. $0.08
    public var loadBalancerMonthly: Double   // e.g. $18.00

    public init(
        providerName: String,
        cpuHourlyPerCore: Double,
        memoryHourlyPerGiB: Double,
        storageMonthlyPerGB: Double,
        loadBalancerMonthly: Double = 18.00
    ) {
        self.providerName = providerName
        self.cpuHourlyPerCore = cpuHourlyPerCore
        self.memoryHourlyPerGiB = memoryHourlyPerGiB
        self.storageMonthlyPerGB = storageMonthlyPerGB
        self.loadBalancerMonthly = loadBalancerMonthly
    }

    public static let aws = CloudPricingProfile(
        providerName: "AWS (m6i / gp3)",
        cpuHourlyPerCore: 0.0316,
        memoryHourlyPerGiB: 0.0042,
        storageMonthlyPerGB: 0.08
    )

    public static let gcp = CloudPricingProfile(
        providerName: "GCP (n2 / pd-standard)",
        cpuHourlyPerCore: 0.0316,
        memoryHourlyPerGiB: 0.0042,
        storageMonthlyPerGB: 0.075
    )

    public static let azure = CloudPricingProfile(
        providerName: "Azure (Dsv5 / SSD)",
        cpuHourlyPerCore: 0.0320,
        memoryHourlyPerGiB: 0.0040,
        storageMonthlyPerGB: 0.08
    )

    public static let standard = aws
}

/// Detailed cost breakdown in USD for a given object or cluster slice.
public struct FinOpsCostBreakdown: Codable, Equatable, Sendable {
    public var cpuCost: Double
    public var memoryCost: Double
    public var storageCost: Double
    public var networkCost: Double
    public var idleCost: Double
    public var totalCost: Double

    public init(
        cpuCost: Double = 0,
        memoryCost: Double = 0,
        storageCost: Double = 0,
        networkCost: Double = 0,
        idleCost: Double = 0,
        totalCost: Double = 0
    ) {
        self.cpuCost = cpuCost
        self.memoryCost = memoryCost
        self.storageCost = storageCost
        self.networkCost = networkCost
        self.idleCost = idleCost
        self.totalCost = totalCost > 0 ? totalCost : (cpuCost + memoryCost + storageCost + networkCost + idleCost)
    }

    public static let zero = FinOpsCostBreakdown()
}

/// An individual line item in the FinOps allocation matrix (e.g. a namespace, workload, or node).
public struct FinOpsAllocationRow: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var namespace: String?
    public var breakdown: FinOpsCostBreakdown
    public var efficiencyScore: Double      // 0.0 to 1.0 (1.0 = 100% utilized, no waste)
    public var estimatedWasteUSD: Double    // Unutilized paid capacity in USD for the window
    public var monthlyRunRateUSD: Double    // Extrapolated monthly spend
    public var resourceKind: String?

    public init(
        id: String,
        name: String,
        namespace: String? = nil,
        breakdown: FinOpsCostBreakdown,
        efficiencyScore: Double,
        estimatedWasteUSD: Double,
        monthlyRunRateUSD: Double,
        resourceKind: String? = nil
    ) {
        self.id = id
        self.name = name
        self.namespace = namespace
        self.breakdown = breakdown
        self.efficiencyScore = max(0.0, min(1.0, efficiencyScore))
        self.estimatedWasteUSD = max(0.0, estimatedWasteUSD)
        self.monthlyRunRateUSD = max(0.0, monthlyRunRateUSD)
        self.resourceKind = resourceKind
    }
}

/// Trend point for spend over time stacked charts.
public struct FinOpsTimeSeriesPoint: Identifiable, Codable, Equatable, Sendable {
    public var id: String { "\(date.timeIntervalSince1970)" }
    public var date: Date
    public var label: String
    public var totalCost: Double
    public var costByCategory: [String: Double]

    public init(date: Date, label: String, totalCost: Double, costByCategory: [String: Double] = [:]) {
        self.date = date
        self.label = label
        self.totalCost = totalCost
        self.costByCategory = costByCategory
    }
}

/// Severity level of a FinOps cost-saving recommendation.
public enum FinOpsSeverity: String, Codable, Sendable {
    case critical
    case warning
    case info

    public var badgeLabel: String {
        switch self {
        case .critical: return "High Impact"
        case .warning: return "Moderate"
        case .info: return "Optimization"
        }
    }
}

/// Actionable cost optimization suggestion generated by the FinOps advisor.
public struct FinOpsRecommendation: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var targetResource: String
    public var namespace: String?
    public var monthlySavingsUSD: Double
    public var severity: FinOpsSeverity
    public var currentAllocation: String
    public var suggestedAllocation: String
    public var yamlPatchSnippet: String?
    public var confidence: String
    public var safetyHeadroom: String
    public var verificationCommand: String?
    public var dryRunCommand: String?
    public var riskLevel: String

    public init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String,
        targetResource: String,
        namespace: String? = nil,
        monthlySavingsUSD: Double,
        severity: FinOpsSeverity,
        currentAllocation: String,
        suggestedAllocation: String,
        yamlPatchSnippet: String? = nil,
        confidence: String = "High · Verified Metrics",
        safetyHeadroom: String = "+35% Headroom · Limits Retained",
        verificationCommand: String? = nil,
        dryRunCommand: String? = nil,
        riskLevel: String = "Low Risk"
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.targetResource = targetResource
        self.namespace = namespace
        self.monthlySavingsUSD = monthlySavingsUSD
        self.severity = severity
        self.currentAllocation = currentAllocation
        self.suggestedAllocation = suggestedAllocation
        self.yamlPatchSnippet = yamlPatchSnippet
        self.confidence = confidence
        self.safetyHeadroom = safetyHeadroom
        self.verificationCommand = verificationCommand
        self.dryRunCommand = dryRunCommand
        self.riskLevel = riskLevel
    }
}

/// Status of the cost monitoring data source.
public enum FinOpsDataSourceStatus: Equatable, Sendable {
    case openCostConnected(service: String, namespace: String)
    case kubecostConnected(service: String, namespace: String)
    case builtInEstimation(profile: CloudPricingProfile)

    public var isExternalProvider: Bool {
        switch self {
        case .openCostConnected, .kubecostConnected: return true
        case .builtInEstimation: return false
        }
    }

    public var displayTitle: String {
        switch self {
        case .openCostConnected(let service, _):
            return "OpenCost Live (\(service))"
        case .kubecostConnected(let service, _):
            return "Kubecost Live (\(service))"
        case .builtInEstimation(let profile):
            return "Cloud Estimation (\(profile.providerName))"
        }
    }
}

/// High-level KPIs and summaries for the FinOps cockpit.
public struct FinOpsSummary: Codable, Equatable, Sendable {
    public var windowSpendUSD: Double
    public var monthlyRunRateUSD: Double
    public var potentialMonthlySavingsUSD: Double
    public var overallEfficiencyScore: Double   // 0.0 to 1.0
    public var totalCoresAllocated: Double
    public var totalMemoryGiBAllocated: Double
    public var totalStorageGiBAllocated: Double
    public var totalCoresUsed: Double
    public var totalMemoryGiBUsed: Double
    public var totalIdleCostUSD: Double
    public var totalComputeCostUSD: Double
    public var totalMemoryCostUSD: Double
    public var totalStorageCostUSD: Double

    public init(
        windowSpendUSD: Double,
        monthlyRunRateUSD: Double,
        potentialMonthlySavingsUSD: Double,
        overallEfficiencyScore: Double,
        totalCoresAllocated: Double,
        totalMemoryGiBAllocated: Double,
        totalStorageGiBAllocated: Double,
        totalCoresUsed: Double = 0,
        totalMemoryGiBUsed: Double = 0,
        totalIdleCostUSD: Double = 0,
        totalComputeCostUSD: Double = 0,
        totalMemoryCostUSD: Double = 0,
        totalStorageCostUSD: Double = 0
    ) {
        self.windowSpendUSD = windowSpendUSD
        self.monthlyRunRateUSD = monthlyRunRateUSD
        self.potentialMonthlySavingsUSD = potentialMonthlySavingsUSD
        self.overallEfficiencyScore = overallEfficiencyScore
        self.totalCoresAllocated = totalCoresAllocated
        self.totalMemoryGiBAllocated = totalMemoryGiBAllocated
        self.totalStorageGiBAllocated = totalStorageGiBAllocated
        self.totalCoresUsed = totalCoresUsed
        self.totalMemoryGiBUsed = totalMemoryGiBUsed
        self.totalIdleCostUSD = totalIdleCostUSD
        self.totalComputeCostUSD = totalComputeCostUSD
        self.totalMemoryCostUSD = totalMemoryCostUSD
        self.totalStorageCostUSD = totalStorageCostUSD
    }

    public static let zero = FinOpsSummary(
        windowSpendUSD: 0,
        monthlyRunRateUSD: 0,
        potentialMonthlySavingsUSD: 0,
        overallEfficiencyScore: 1.0,
        totalCoresAllocated: 0,
        totalMemoryGiBAllocated: 0,
        totalStorageGiBAllocated: 0,
        totalCoresUsed: 0,
        totalMemoryGiBUsed: 0,
        totalIdleCostUSD: 0,
        totalComputeCostUSD: 0,
        totalMemoryCostUSD: 0,
        totalStorageCostUSD: 0
    )
}

/// The complete FinOps report rendered by the CTX FinOps center.
public struct FinOpsReport: Sendable {
    public var window: FinOpsTimeWindow
    public var aggregation: FinOpsAggregation
    public var summary: FinOpsSummary
    public var rows: [FinOpsAllocationRow]
    public var timeSeries: [FinOpsTimeSeriesPoint]
    public var recommendations: [FinOpsRecommendation]
    public var dataSource: FinOpsDataSourceStatus
    public var hasLivePodTelemetry: Bool

    public init(
        window: FinOpsTimeWindow,
        aggregation: FinOpsAggregation,
        summary: FinOpsSummary,
        rows: [FinOpsAllocationRow],
        timeSeries: [FinOpsTimeSeriesPoint],
        recommendations: [FinOpsRecommendation],
        dataSource: FinOpsDataSourceStatus,
        hasLivePodTelemetry: Bool = true
    ) {
        self.window = window
        self.aggregation = aggregation
        self.summary = summary
        self.rows = rows
        self.timeSeries = timeSeries
        self.recommendations = recommendations
        self.dataSource = dataSource
        self.hasLivePodTelemetry = hasLivePodTelemetry
    }
}
