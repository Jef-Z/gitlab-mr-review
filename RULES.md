# Code Review Rules

违反以下规则一律标记为 **CRITICAL**。

## 禁止使用的 API

| 禁止 | 原因 | 替代方案 |
|------|------|---------|
| `jest.clearAllMocks()` | 已经配置了Jest全局配置 | 移除 |

## 代码风格

| 规则 | 错误示例 | 正确示例 |
|------|---------|---------|
| `if` 单行执行体必须加大括号 | `if (!obj) return undefined;` | `if (!obj) { return undefined; }` |

---

## 测试文件例外（`*.test.ts` / `*.test.tsx` / `*.spec.ts` / `*.spec.tsx` / `__tests__/**`）

测试代码的目标是**清晰表达意图**与**快速定位失败**，与生产代码不同。Review 单测文件时应放宽以下事项：

### 不要评论的内容（测试文件内合法）

| 事项 | 为什么在测试里没问题 |
|------|--------------------|
| `value as SomeType` / `as unknown as T` 等类型断言 | 测试里常用于构造最小可运行的 mock/fixture；**只要测试本身跑通且断言正确**，就不是问题。不要建议改成完整类型或类型守卫。 |
| 未处理的"边界异常"、空值 | 测试本来就是在喂边界；应由 `expect(...).toThrow(...)` 等断言覆盖，而不是加 try/catch |
| 重复的 setup / arrange 代码 | 测试优先 **DAMP（Descriptive And Meaningful Phrases）** 而非 DRY，内联 setup 通常更易读 |
| 魔法值（`expect(x).toBe(42)`） | 常量化反而让断言失去意义 |
| 性能 / N+1 查询 / 复杂度 | 测试不在热路径 |
| 变量命名简短（`a`, `b`, `input`） | test case 作用域小，局部可读即可 |

### 测试文件**独有**的应标记问题

| 问题 | 严重度 | 说明 |
|------|-------|------|
| `test.only` / `describe.only` / `fit` / `fdescribe` 遗留 | CRITICAL | 会让 CI 只跑这一条，其他测试被跳过 |
| `test.skip` / `xit` / `xdescribe` 且无注释说明原因 | WARNING | 被跳过的测试等于没有，必须有跳过理由 |
| 条件断言：`if (cond) expect(...)` | CRITICAL | 条件不满足时无断言，测试永远绿 |
| 测试里没有任何 `expect`（或只有 `toBeDefined()` 这类空断言） | CRITICAL | 没断言的"测试"不是测试 |
| `await` 缺失导致 Promise 未等待 | CRITICAL | 异步断言未执行就结束，假绿 |
| 过度 mock，mock 了被测对象本身的方法 | WARNING | 测的是 mock 不是实现 |
| 共享可变状态污染其他用例（未在 `beforeEach` 重置） | WARNING | 顺序耦合，难以定位失败 |

### 严重度通用指引

生产代码里的 CRITICAL 在测试里若不影响测试正确性，可**降级为 SUGGESTION 或不提**。判断标准：该问题是否会让测试**假绿**（通过但并未真正验证）或让 CI 行为异常？是 → 提；否 → 不提。

