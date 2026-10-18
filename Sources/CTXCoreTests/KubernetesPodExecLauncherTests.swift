import CTXCore

func runKubernetesPodExecLauncherTests() {
    let valid = KubernetesPodExecLauncher.Request(
        namespace: "platform",
        podName: "api-7fd69-xyz",
        container: "app"
    )
    assert(KubernetesPodExecLauncher.validate(valid) == nil)

    let hostile = KubernetesPodExecLauncher.Request(
        namespace: "platform; rm -rf /",
        podName: "api-7fd69-xyz"
    )
    assert(KubernetesPodExecLauncher.validate(hostile) != nil)

    let context = KubernetesContextProfile(
        contextName: "test-context",
        clusterName: "test-cluster",
        userName: "test-user",
        namespace: "default",
        kubeconfigPath: "/tmp/test-kubeconfig"
    )
    let arguments = KubernetesPodExecLauncher.arguments(context: context, request: valid)
    assert(arguments.contains("--kubeconfig"))
    assert(arguments.contains("/tmp/test-kubeconfig"))
    assert(arguments.contains("--container"))
    assert(arguments.contains("app"))
    assert(arguments.suffix(4) == ["--", "sh", "-c", "command -v bash >/dev/null 2>&1 && exec bash || exec sh"])
}
