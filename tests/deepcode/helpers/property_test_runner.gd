class_name PropertyTestRunner
extends RefCounted
## 属性测试运行器：对给定的测试函数执行 N 次随机迭代，汇总结果。
## test_callable 签名: func(rng: RandomNumberGenerator, iteration: int) -> String
## 返回空字符串表示通过，非空字符串为失败原因。


func run_property(property_name: String, iterations: int, test_callable: Callable) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var passed: int = 0
	var failed: int = 0
	var first_failure: String = ""

	for i in range(iterations):
		var result: String = test_callable.call(rng, i)
		if result.is_empty():
			passed += 1
		else:
			failed += 1
			if first_failure.is_empty():
				first_failure = "Iteration %d: %s" % [i, result]

	var success: bool = failed == 0
	var summary: String = ""
	if success:
		summary = "[PASS] %s (%d/%d iterations passed)" % [property_name, passed, iterations]
	else:
		summary = "[FAIL] %s (%d/%d failed, first: %s)" % [property_name, failed, iterations, first_failure]

	return {
		"success": success,
		"passed": passed,
		"failed": failed,
		"iterations": iterations,
		"first_failure": first_failure,
		"summary": summary,
	}
