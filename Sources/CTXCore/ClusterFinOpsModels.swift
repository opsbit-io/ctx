import Foundation

// MARK: - FinOps & Cloud Cost Data Models

/// Time window for financial cost allocation and run-rate analysis.
public enum FinOpsTimeWindow: String, CaseIterable, Identifiable, Codable, Sendable {
    case h24 = "24h"
    case d7 = "7d"
    case d30 = "30d"
    case monthToDate = "month"
    case custom = "custom"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .h24: return "Last 24 Hours"
        case .d7: return "Last 7 Days"
        case .d30: return "Last 30 Days"
        case .monthToDate: return "Month to Date"
        case .custom: return "Custom Range"
        }
    }

    public var shortName: String {
        switch self {
        case .h24: return "24 Hours"
        case .d7: return "7 Days"
        case .d30: return "30 Days"
        case .monthToDate: return "Month to Date"
        case .custom: return "Custom Range"
        }
    }

    public var daysFactor: Double {
        switch self {
        case .h24: return 1.0
        case .d7: return 7.0
        case .d30: return 30.0
        case .monthToDate: return max(1.0, Double(Calendar.current.component(.day, from: Date())))
        case .custom: return 7.0
        }
    }

    public var monthlyMultiplier: Double {
        switch self {
        case .h24: return 30.0
        case .d7: return 30.0 / 7.0
        case .d30: return 1.0
        case .monthToDate: return 30.0 / max(1.0, Double(Calendar.current.component(.day, from: Date())))
        case .custom: return 30.0 / 7.0
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

    /// CTX cannot derive cloud billing rates from Kubernetes inventory alone.
    /// A profile is usable only when an explicit integration or caller supplied rates.
    public var hasExplicitRates: Bool {
        cpuHourlyPerCore > 0 || memoryHourlyPerGiB > 0 || storageMonthlyPerGB > 0 || loadBalancerMonthly > 0
    }

    public static let aws = CloudPricingProfile(
        providerName: "AWS pricing unavailable",
        cpuHourlyPerCore: 0,
        memoryHourlyPerGiB: 0,
        storageMonthlyPerGB: 0,
        loadBalancerMonthly: 0
    )

    public static let gcp = CloudPricingProfile(
        providerName: "GCP pricing unavailable",
        cpuHourlyPerCore: 0,
        memoryHourlyPerGiB: 0,
        storageMonthlyPerGB: 0,
        loadBalancerMonthly: 0
    )

    public static let azure = CloudPricingProfile(
        providerName: "Azure pricing unavailable",
        cpuHourlyPerCore: 0,
        memoryHourlyPerGiB: 0,
        storageMonthlyPerGB: 0,
        loadBalancerMonthly: 0
    )

    public static let standard = CloudPricingProfile(
        providerName: "Pricing unavailable",
        cpuHourlyPerCore: 0,
        memoryHourlyPerGiB: 0,
        storageMonthlyPerGB: 0,
        loadBalancerMonthly: 0
    )
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
    /// True only when the efficiency value is backed by a current metrics sample.
    public var hasLiveUsage: Bool
    public var cpuCoresRequested: Double
    public var cpuCoresUsed: Double
    public var memoryGiBRequested: Double
    public var memoryGiBUsed: Double
    public var storageGiB: Double

    public init(
        id: String,
        name: String,
        namespace: String? = nil,
        breakdown: FinOpsCostBreakdown,
        efficiencyScore: Double,
        estimatedWasteUSD: Double,
        monthlyRunRateUSD: Double,
        resourceKind: String? = nil,
        hasLiveUsage: Bool = false,
        cpuCoresRequested: Double = 0,
        cpuCoresUsed: Double = 0,
        memoryGiBRequested: Double = 0,
        memoryGiBUsed: Double = 0,
        storageGiB: Double = 0
    ) {
        self.id = id
        self.name = name
        self.namespace = namespace
        self.breakdown = breakdown
        self.efficiencyScore = max(0.0, min(1.0, efficiencyScore))
        self.estimatedWasteUSD = max(0.0, estimatedWasteUSD)
        self.monthlyRunRateUSD = max(0.0, monthlyRunRateUSD)
        self.resourceKind = resourceKind
        self.hasLiveUsage = hasLiveUsage
        self.cpuCoresRequested = cpuCoresRequested
        self.cpuCoresUsed = cpuCoresUsed
        self.memoryGiBRequested = memoryGiBRequested
        self.memoryGiBUsed = memoryGiBUsed
        self.storageGiB = storageGiB
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
        confidence: String = KubernetesGitOpsService.unknownValue,
        safetyHeadroom: String = KubernetesGitOpsService.unknownValue,
        verificationCommand: String? = nil,
        dryRunCommand: String? = nil,
        riskLevel: String = KubernetesGitOpsService.unknownValue
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
    case openCostAgent(endpoint: String, version: String)
    case kubecostAgent(endpoint: String)
    case builtInEstimation(profile: CloudPricingProfile)

    public var badgeTitle: String {
        switch self {
        case .openCostAgent(_, let version):
            return version.isEmpty ? "OpenCost" : "OpenCost \(version)"
        case .kubecostAgent:
            return "Kubecost Verified"
        case .builtInEstimation(let profile):
            return profile.hasExplicitRates ? "Estimated · \(profile.providerName)" : profile.providerName
        }
    }

    public var isLiveAgent: Bool {
        switch self {
        case .openCostAgent, .kubecostAgent:
            return true
        case .builtInEstimation:
            return false
        }
    }
}

/// Comprehensive FinOps cost analysis report.
public struct FinOpsReport: Equatable, Sendable {
    public var window: FinOpsTimeWindow
    public var aggregation: FinOpsAggregation
    public var summary: FinOpsSummary
    public var rows: [FinOpsAllocationRow]
    public var timeSeries: [FinOpsTimeSeriesPoint]
    public var recommendations: [FinOpsRecommendation]
    public var dataSource: FinOpsDataSourceStatus
    public var hasLivePodTelemetry: Bool

    public init(
        window: FinOpsTimeWindow = .h24,
        aggregation: FinOpsAggregation = .namespace,
        summary: FinOpsSummary = .zero,
        rows: [FinOpsAllocationRow] = [],
        timeSeries: [FinOpsTimeSeriesPoint] = [],
        recommendations: [FinOpsRecommendation] = [],
        dataSource: FinOpsDataSourceStatus = .builtInEstimation(profile: .standard),
        hasLivePodTelemetry: Bool = false
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

/// High-level financial summary of the cluster during the active analysis window.
public struct FinOpsSummary: Equatable, Sendable {
    public var windowSpendUSD: Double
    public var monthlyRunRateUSD: Double
    public var potentialMonthlySavingsUSD: Double
    public var overallEfficiencyScore: Double

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
        windowSpendUSD: Double = 0,
        monthlyRunRateUSD: Double = 0,
        potentialMonthlySavingsUSD: Double = 0,
        overallEfficiencyScore: Double = 0,
        totalCoresAllocated: Double = 0,
        totalMemoryGiBAllocated: Double = 0,
        totalStorageGiBAllocated: Double = 0,
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

    public static let zero = FinOpsSummary()
}
