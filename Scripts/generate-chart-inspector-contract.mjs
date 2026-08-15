#!/usr/bin/env node

import { readFile, mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const contractPath = resolve(repositoryRoot, "Contracts/ChartInspectorContract.json");
const outputs = [
  {
    path: resolve(
      repositoryRoot,
      "VercelAnalyticsBar/Features/ChartInspector/Generated/ChartInspectorContract.generated.swift",
    ),
    render: renderSwift,
  },
  {
    path: resolve(repositoryRoot, "Tools/ChartInspector/src/generated/contract.ts"),
    render: renderTypeScript,
  },
  {
    path: resolve(repositoryRoot, "Tools/ChartInspector/src/generated/inspector-adapter.ts"),
    render: renderTypeScriptInspectorAdapter,
  },
];

const checkOnly = process.argv.slice(2).includes("--check");
const contract = JSON.parse(await readFile(contractPath, "utf8"));
validateContract(contract);

let hasStaleOutput = false;
for (const output of outputs) {
  const expected = output.render(contract);
  if (checkOnly) {
    const current = await readFile(output.path, "utf8").catch(() => undefined);
    if (current !== expected) {
      hasStaleOutput = true;
      console.error(`Generated contract is stale: ${relativePath(output.path)}`);
    }
  } else {
    await mkdir(dirname(output.path), { recursive: true });
    await writeFile(output.path, expected);
    console.log(`Generated ${relativePath(output.path)}`);
  }
}

if (hasStaleOutput) {
  console.error("Run `npm --prefix Tools/ChartInspector run contract:generate` and commit the result.");
  process.exitCode = 1;
}

function validateContract(value) {
  const { protocol, style, listStyle } = value;
  const revisions = protocol?.revisions;
  if (
    !Number.isInteger(protocol?.version) ||
    !Number.isInteger(revisions?.nativeMinimum) ||
    !Number.isInteger(revisions?.styleChangeMinimum) ||
    !Number.isInteger(revisions?.maximum) ||
    revisions.nativeMinimum < 0 ||
    revisions.nativeMinimum >= revisions.styleChangeMinimum ||
    revisions.styleChangeMinimum > revisions.maximum
  ) {
    throw new Error("Protocol version and revision bounds must be ordered integers.");
  }
  if (typeof protocol.sources?.web !== "string" || typeof protocol.sources?.native !== "string") {
    throw new Error("Protocol sources must be strings.");
  }
  if (!Array.isArray(protocol.messages?.webIncoming) || typeof protocol.messages.nativeState !== "string") {
    throw new Error("Protocol message names are required.");
  }
  if (!Array.isArray(style?.fields) || style.fields.length === 0) {
    throw new Error("At least one style field is required.");
  }
  if (
    typeof style.color?.accent !== "string" ||
    typeof style.color?.hexPattern !== "string" ||
    style.color?.canonicalHexCase !== "upper"
  ) {
    throw new Error("The supported color contract requires an accent, hex pattern, and uppercase output.");
  }

  const names = new Set();
  const inspectorPaths = new Set();
  for (const field of style.fields) {
    if (typeof field.name !== "string" || names.has(field.name)) {
      throw new Error(`Style field names must be unique: ${field.name}`);
    }
    names.add(field.name);
    if (!["boolean", "color", "enum", "integer", "number"].includes(field.type)) {
      throw new Error(`Unsupported style field type: ${field.type}`);
    }
    if (field.type === "enum" && !Array.isArray(style.enums?.[field.enum])) {
      throw new Error(`Missing enum values for ${field.name}.`);
    }
    if (["integer", "number"].includes(field.type)) {
      if (![field.default, field.minimum, field.maximum, field.step].every(Number.isFinite)) {
        throw new Error(`Numeric metadata is incomplete for ${field.name}.`);
      }
      if (field.minimum > field.default || field.default > field.maximum || field.step <= 0) {
        throw new Error(`Numeric metadata is invalid for ${field.name}.`);
      }
    }

    const inspector = field.inspector;
    const identifierPattern = /^[A-Za-z_$][A-Za-z0-9_$]*$/;
    if (
      typeof inspector?.group !== "string" ||
      !identifierPattern.test(inspector.group) ||
      typeof inspector?.key !== "string" ||
      !identifierPattern.test(inspector.key)
    ) {
      throw new Error(`Inspector group and key are required identifiers for ${field.name}.`);
    }
    const inspectorPath = `${inspector.group}.${inspector.key}`;
    if (!inspectorPaths.add(inspectorPath)) {
      throw new Error(`Inspector paths must be unique: ${inspectorPath}.`);
    }
    const expectedControl = {
      boolean: "boolean",
      color: "color",
      enum: "select",
      integer: "range",
      number: "range",
    }[field.type];
    if (inspector.control !== expectedControl) {
      throw new Error(`Inspector control is incompatible with ${field.name}.`);
    }
    if (field.type === "color") {
      const accentDisplay = inspector.accentDisplay;
      if (typeof accentDisplay !== "string" || !new RegExp(style.color.hexPattern).test(accentDisplay)) {
        throw new Error(`Inspector accent display color is invalid for ${field.name}.`);
      }
    } else if (inspector.accentDisplay !== undefined) {
      throw new Error(`Inspector accent display is only valid for color fields: ${field.name}.`);
    }
  }

  if (!Array.isArray(listStyle?.fields) || listStyle.fields.length === 0) {
    throw new Error("At least one list style field is required.");
  }
  validateComponentFields(listStyle.fields, style, "List style");
}

function validateComponentFields(fields, sharedStyle, componentName) {
  const names = new Set();
  const inspectorPaths = new Set();
  for (const field of fields) {
    if (typeof field.name !== "string" || names.has(field.name)) {
      throw new Error(`${componentName} field names must be unique: ${field.name}`);
    }
    names.add(field.name);
    if (!['boolean', 'color', 'enum', 'integer', 'number'].includes(field.type)) {
      throw new Error(`Unsupported ${componentName.toLowerCase()} field type: ${field.type}`);
    }
    if (field.type === "enum" && !Array.isArray(sharedStyle.enums?.[field.enum])) {
      throw new Error(`Missing enum values for ${field.name}.`);
    }
    if (["integer", "number"].includes(field.type)) {
      if (![field.default, field.minimum, field.maximum, field.step].every(Number.isFinite)) {
        throw new Error(`Numeric metadata is incomplete for ${field.name}.`);
      }
      if (field.minimum > field.default || field.default > field.maximum || field.step <= 0) {
        throw new Error(`Numeric metadata is invalid for ${field.name}.`);
      }
    }
    const inspector = field.inspector;
    const identifierPattern = /^[A-Za-z_$][A-Za-z0-9_$]*$/;
    if (
      typeof inspector?.group !== "string" ||
      !identifierPattern.test(inspector.group) ||
      typeof inspector?.key !== "string" ||
      !identifierPattern.test(inspector.key)
    ) {
      throw new Error(`Inspector group and key are required identifiers for ${field.name}.`);
    }
    const inspectorPath = `${inspector.group}.${inspector.key}`;
    if (!inspectorPaths.add(inspectorPath)) {
      throw new Error(`Inspector paths must be unique: ${inspectorPath}.`);
    }
    const expectedControl = {
      boolean: "boolean",
      color: "color",
      enum: "select",
      integer: "range",
      number: "range",
    }[field.type];
    if (inspector.control !== expectedControl) {
      throw new Error(`Inspector control is incompatible with ${field.name}.`);
    }
    if (field.type === "color") {
      const accentDisplay = inspector.accentDisplay;
      if (typeof accentDisplay !== "string" || !new RegExp(sharedStyle.color.hexPattern).test(accentDisplay)) {
        throw new Error(`Inspector accent display color is invalid for ${field.name}.`);
      }
    } else if (inspector.accentDisplay !== undefined) {
      throw new Error(`Inspector accent display is only valid for color fields: ${field.name}.`);
    }
  }
}

function renderSwift({ protocol, style }) {
  return renderComponentSwift(arguments[0]);

  const fields = style.fields;
  const enums = Object.entries(style.enums);
  const properties = fields.map((field) => `    let ${field.name}: ${swiftType(field)}`).join("\n");
  const parameters = fields
    .map((field) => `        ${field.name}: ${swiftType(field)}`)
    .join(",\n");
  const assignments = fields.map((field) => `        self.${field.name} = ${field.name}`).join("\n");
  const validations = fields
    .filter((field) => field.type === "number" || field.type === "integer")
    .map((field) => {
      const value = field.type === "integer" ? `Double(${field.name})` : field.name;
      return `        try Self.validate(
            ${value},
            field: "${field.name}",
            range: Self.${field.name}Range
        )`;
    })
    .join("\n");
  const ranges = fields
    .filter((field) => field.type === "number" || field.type === "integer")
    .map(
      (field) =>
        `    static let ${field.name}Range = ${swiftDouble(field.minimum)} ... ${swiftDouble(field.maximum)}`,
    )
    .join("\n");
  const defaults = fields
    .map((field) => `                ${field.name}: ${swiftDefault(field, style)}`)
    .join(",\n");
  const decoding = fields
    .map(
      (field) =>
        `            ${field.name}: container.decode(${swiftType(field)}.self, forKey: .${field.name})`,
    )
    .join(",\n");
  const enumDeclarations = enums
    .map(([name, values]) => {
      const cases = values.map((value) => `    case ${value}`).join("\n");
      return `enum ${swiftEnumName(name)}: String, Codable, CaseIterable, Sendable {\n${cases}\n}`;
    })
    .join("\n\n");
  const incomingCases = protocol.messages.webIncoming.map((name) => `        case ${name}`).join("\n");

  return `// Generated by Scripts/generate-chart-inspector-contract.mjs.
// Source: Contracts/ChartInspectorContract.json. Do not edit directly.
// swiftlint:disable file_length

import Foundation

enum ChartColor: Equatable, Sendable {
    case accent
    case rgb(red: UInt8, green: UInt8, blue: UInt8)

    init?(rawValue: String) {
        if rawValue == ${swiftString(style.color.accent)} {
            self = .accent
            return
        }

        guard rawValue.count == 7, rawValue.first == "#" else { return nil }
        let hex = rawValue.dropFirst()
        guard let red = UInt8(hex.prefix(2), radix: 16),
              let green = UInt8(hex.dropFirst(2).prefix(2), radix: 16),
              let blue = UInt8(hex.suffix(2), radix: 16)
        else {
            return nil
        }
        self = .rgb(red: red, green: green, blue: blue)
    }

    var rawValue: String {
        switch self {
        case .accent:
            ${swiftString(style.color.accent)}
        case let .rgb(red, green, blue):
            String(format: "#%02X%02X%02X", red, green, blue)
        }
    }
}

extension ChartColor: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let color = ChartColor(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected accent or a six-digit hexadecimal color."
            )
        }
        self = color
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

${enumDeclarations}

enum ChartStyleValidationError: Error, Equatable {
    case outOfRange(field: String, range: ClosedRange<Double>)
}

// swiftlint:disable:next type_body_length
struct ChartStyle: Codable, Equatable, Sendable {
${ranges}

    static let \`default\`: ChartStyle = {
        do {
            return try ChartStyle(
${defaults}
            )
        } catch {
            preconditionFailure("The contract-defined chart style must be valid: \\(error)")
        }
    }()

${properties}

    // swiftlint:disable:next function_body_length
    init(
${parameters}
    ) throws {
${validations}

${assignments}
    }

    // swiftlint:disable:next function_body_length
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
${decoding}
        )
    }

    private static func validate(
        _ value: Double,
        field: String,
        range: ClosedRange<Double>
    ) throws {
        guard value.isFinite, range.contains(value) else {
            throw ChartStyleValidationError.outOfRange(field: field, range: range)
        }
    }
}

#if CHART_INSPECTOR
    enum ChartInspectorProtocol {
        static let version = ${protocol.version}
        static let minimumRevision = ${swiftInteger(protocol.revisions.nativeMinimum)}
        static let firstStyleChangeRevision = ${swiftInteger(protocol.revisions.styleChangeMinimum)}
        static let maximumRevision = ${swiftInteger(protocol.revisions.maximum)}
        static let styleChangeRevisionRange = firstStyleChangeRevision ... maximumRevision
        static let webSource = ${swiftString(protocol.sources.web)}
        static let nativeSource = ${swiftString(protocol.sources.native)}
        static let nativeStateMessage = ${swiftString(protocol.messages.nativeState)}
    }

    enum ChartInspectorIncomingMessageType: String, Codable {
${incomingCases}
    }
#endif
`;
}

function renderTypeScript({ protocol, style }) {
  return renderComponentTypeScript(arguments[0]);

  const enumTypes = Object.entries(style.enums)
    .map(([name, values]) => {
      const typeName = typeScriptEnumName(name);
      const valuesName = constantName(name, "VALUES");
      return `export const ${valuesName} = ${JSON.stringify(values)} as const;\nexport type ${typeName} = (typeof ${valuesName})[number];`;
    })
    .join("\n\n");
  const fields = style.fields
    .map((field) => `  ${field.name}: ${typeScriptType(field)};`)
    .join("\n");
  const defaults = style.fields
    .map((field) => `  ${field.name}: ${JSON.stringify(field.default)},`)
    .join("\n");
  const ranges = style.fields
    .filter((field) => field.type === "number" || field.type === "integer")
    .map(
      (field) =>
        `  ${field.name}: { minimum: ${field.minimum}, maximum: ${field.maximum}, step: ${field.step}, integer: ${field.type === "integer"} },`,
    )
    .join("\n");
  const validations = style.fields
    .map((field) => `    ${typeScriptValidation(field)}`)
    .join(" &&\n");
  const commandNames = protocol.messages.webIncoming.filter(
    (name) => name !== "ready" && name !== "styleChanged",
  );

  return `// Generated by Scripts/generate-chart-inspector-contract.mjs.
// Source: Contracts/ChartInspectorContract.json. Do not edit directly.

export const INSPECTOR_PROTOCOL_VERSION = ${protocol.version};
export const MIN_INSPECTOR_REVISION = ${protocol.revisions.nativeMinimum};
export const FIRST_STYLE_CHANGE_REVISION = ${protocol.revisions.styleChangeMinimum};
export const MAX_INSPECTOR_REVISION = ${protocol.revisions.maximum};
export const INSPECTOR_SOURCE = ${JSON.stringify(protocol.sources.web)};
export const NATIVE_SOURCE = ${JSON.stringify(protocol.sources.native)};
export const NATIVE_STATE_MESSAGE = ${JSON.stringify(protocol.messages.nativeState)};

${enumTypes}

export interface ChartStyle {
${fields}
}

export const CHART_STYLE_DEFAULT: ChartStyle = {
${defaults}
};

export const CHART_STYLE_RANGES = {
${ranges}
} as const;

export interface NativeStateMessage {
  protocolVersion: number;
  type: typeof NATIVE_STATE_MESSAGE;
  source: string;
  revision: number;
  values: ChartStyle;
}

export interface WebReadyMessage {
  protocolVersion: number;
  type: "ready";
  source: string;
}

export interface WebStyleChangedMessage {
  protocolVersion: number;
  type: "styleChanged";
  source: string;
  revision: number;
  values: ChartStyle;
}

export interface WebCommandMessage {
  protocolVersion: number;
  type: ${commandNames.map((name) => JSON.stringify(name)).join(" | ")};
  source: string;
}

export type WebMessage = WebReadyMessage | WebStyleChangedMessage | WebCommandMessage;

export function isChartStyle(value: unknown): value is ChartStyle {
  if (!isRecord(value)) {
    return false;
  }
  return (
${validations}
  );
}

function isChartColor(value: unknown): value is string {
  return value === ${JSON.stringify(style.color.accent)} ||
    (typeof value === "string" && /${style.color.hexPattern}/.test(value));
}

function isNumberInRange(value: unknown, minimum: number, maximum: number): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= minimum && value <= maximum;
}

function isOneOf<T extends string>(value: unknown, values: readonly T[]): value is T {
  return typeof value === "string" && values.includes(value as T);
}

function listLayoutFits(
  visibleRowCount: number,
  headerToRowsSpacing: number,
  rowHeight: number,
  rowSpacing: number,
): boolean {
  return 16 + headerToRowsSpacing + visibleRowCount * rowHeight +
    Math.max(visibleRowCount - 1, 0) * rowSpacing <= 144;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
`;
}

function renderTypeScriptInspectorAdapter({ style }) {
  return renderComponentInspectorAdapter(arguments[0]);

  const fields = style.fields;
  const groups = new Map();
  for (const field of fields) {
    const groupFields = groups.get(field.inspector.group) ?? [];
    groupFields.push(field);
    groups.set(field.inspector.group, groupFields);
  }

  const valueImports = [
    "CHART_STYLE_DEFAULT",
    "CHART_STYLE_RANGES",
    ...new Set(
      fields
        .filter((field) => field.type === "enum")
        .map((field) => constantName(field.enum, "VALUES")),
    ),
  ];
  const typeImports = [
    "ChartStyle",
    ...new Set(
      fields
        .filter((field) => field.type === "enum")
        .map((field) => typeScriptEnumName(field.enum)),
    ),
  ];
  const metadata = fields
    .map(
      (field) =>
        `  { name: ${JSON.stringify(field.name)}, path: ${JSON.stringify(`${field.inspector.group}.${field.inspector.key}`)}, control: ${JSON.stringify(field.inspector.control)} },`,
    )
    .join("\n");
  const configGroups = [...groups]
    .map(([group, groupFields]) => {
      const entries = groupFields
        .map((field) => `    ${field.inspector.key}: ${typeScriptInspectorControl(field)},`)
        .join("\n");
      return `  ${group}: {\n${entries}\n  },`;
    })
    .join("\n");
  const styleToDialGroups = [...groups]
    .map(([group, groupFields]) => {
      const entries = groupFields
        .map(
          (field) =>
            `      ${field.inspector.key}: ${typeScriptInspectorStyleValue(field, style)},`,
        )
        .join("\n");
      return `    ${group}: {\n${entries}\n    },`;
    })
    .join("\n");
  const dialToStyleFields = fields
    .map(
      (field) =>
        `    ${field.name}: ${typeScriptInspectorDialValue(field)},`,
    )
    .join("\n");

  return `// Generated by Scripts/generate-chart-inspector-contract.mjs.
// Source: Contracts/ChartInspectorContract.json. Do not edit directly.

import type { ResolvedValues } from "dialkit";
import {
${valueImports.map((name) => `  ${name},`).join("\n")}
} from "./contract";
import type { ${typeImports.join(", ")} } from "./contract";

export const CHART_STYLE_INSPECTOR_FIELDS = [
${metadata}
] as const;

export const chartFieldConfig = {
${configGroups}
};

export function dialValuesFromStyle(style: ChartStyle) {
  return {
${styleToDialGroups}
  };
}

export function styleFromDialValues(values: ResolvedValues<typeof chartFieldConfig>): ChartStyle {
  return {
${dialToStyleFields}
  };
}

function dialRange(
  defaultValue: number,
  range: { minimum: number; maximum: number; step: number },
): [number, number, number, number] {
  return [defaultValue, range.minimum, range.maximum, range.step];
}
`;
}

function renderComponentSwift({ protocol, style, listStyle }) {
  const enumDeclarations = Object.entries(style.enums)
    .map(([name, values]) => {
      const cases = values.map((value) => `    case ${value}`).join("\n");
      return `enum ${swiftEnumName(name)}: String, Codable, CaseIterable, Sendable {\n${cases}\n}`;
    })
    .join("\n\n");
  const chartStyle = renderSwiftStyleStruct({
    style,
    fields: style.fields,
    name: "ChartStyle",
    validationErrorName: "ChartStyleValidationError",
    disableTypeBodyLength: true,
    disableInitializerLength: true,
    disableDecodingLength: true,
  });
  const list = renderSwiftStyleStruct({
    style,
    fields: listStyle.fields,
    name: "BreakdownListStyle",
    validationErrorName: "BreakdownListStyleValidationError",
    disableInitializerLength: true,
    extraValidation: `        try Self.validateLayout(\n            visibleRowCount: visibleRowCount,\n            headerToRowsSpacing: headerToRowsSpacing,\n            rowHeight: rowHeight,\n            rowSpacing: rowSpacing\n        )`,
    extraMembers: `    private static func validateLayout(\n        visibleRowCount: Int,\n        headerToRowsSpacing: Double,\n        rowHeight: Double,\n        rowSpacing: Double\n    ) throws {\n        let rows = Double(visibleRowCount)\n        let totalHeight = 16 + headerToRowsSpacing + rows * rowHeight + max(rows - 1, 0) * rowSpacing\n        guard totalHeight <= 144 else {\n            throw BreakdownListStyleValidationError.layoutOverflow\n        }\n    }`,
    extraErrorCase: "    case layoutOverflow",
  });

  return `// Generated by Scripts/generate-chart-inspector-contract.mjs.
// Source: Contracts/ChartInspectorContract.json. Do not edit directly.
// swiftlint:disable file_length

import Foundation

enum ChartColor: Equatable, Sendable {
    case accent
    case rgb(red: UInt8, green: UInt8, blue: UInt8)

    init?(rawValue: String) {
        if rawValue == ${swiftString(style.color.accent)} {
            self = .accent
            return
        }

        guard rawValue.count == 7, rawValue.first == "#" else { return nil }
        let hex = rawValue.dropFirst()
        guard let red = UInt8(hex.prefix(2), radix: 16),
              let green = UInt8(hex.dropFirst(2).prefix(2), radix: 16),
              let blue = UInt8(hex.suffix(2), radix: 16)
        else {
            return nil
        }
        self = .rgb(red: red, green: green, blue: blue)
    }

    var rawValue: String {
        switch self {
        case .accent:
            ${swiftString(style.color.accent)}
        case let .rgb(red, green, blue):
            String(format: "#%02X%02X%02X", red, green, blue)
        }
    }
}

extension ChartColor: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let color = ChartColor(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected accent or a six-digit hexadecimal color."
            )
        }
        self = color
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

${enumDeclarations}

${chartStyle}

${list}

enum EditableComponent: String, Codable, CaseIterable, Sendable {
    case chart
    case list
}

#if CHART_INSPECTOR
    enum ChartInspectorProtocol {
        static let version = ${protocol.version}
        static let minimumRevision = ${swiftInteger(protocol.revisions.nativeMinimum)}
        static let firstStyleChangeRevision = ${swiftInteger(protocol.revisions.styleChangeMinimum)}
        static let maximumRevision = ${swiftInteger(protocol.revisions.maximum)}
        static let styleChangeRevisionRange = firstStyleChangeRevision ... maximumRevision
        static let webSource = ${swiftString(protocol.sources.web)}
        static let nativeSource = ${swiftString(protocol.sources.native)}
        static let nativeStateMessage = ${swiftString(protocol.messages.nativeState)}
    }

    enum ChartInspectorIncomingMessageType: String, Codable {
${protocol.messages.webIncoming.map((name) => `        case ${name}`).join("\n")}
    }
#endif
`;
}

function renderSwiftStyleStruct({
  style,
  fields,
  name,
  validationErrorName,
  disableTypeBodyLength = false,
  disableInitializerLength = false,
  disableDecodingLength = false,
  extraValidation = "",
  extraMembers = "",
  extraErrorCase = "",
}) {
  const properties = fields.map((field) => `    let ${field.name}: ${swiftType(field)}`).join("\n");
  const parameters = fields.map((field) => `        ${field.name}: ${swiftType(field)}`).join(",\n");
  const assignments = fields.map((field) => `        self.${field.name} = ${field.name}`).join("\n");
  const validations = fields
    .filter((field) => field.type === "number" || field.type === "integer")
    .map((field) => {
      const value = field.type === "integer" ? `Double(${field.name})` : field.name;
      return `        try Self.validate(\n            ${value},\n            field: "${field.name}",\n            range: Self.${field.name}Range\n        )`;
    })
    .join("\n");
  const ranges = fields
    .filter((field) => field.type === "number" || field.type === "integer")
    .map((field) => `    static let ${field.name}Range = ${swiftDouble(field.minimum)} ... ${swiftDouble(field.maximum)}`)
    .join("\n");
  const defaults = fields.map((field) => `                ${field.name}: ${swiftDefault(field, style)}`).join(",\n");
  const decoding = fields
    .map((field) => `            ${field.name}: container.decode(${swiftType(field)}.self, forKey: .${field.name})`)
    .join(",\n");

  return `enum ${validationErrorName}: Error, Equatable {
    case outOfRange(field: String, range: ClosedRange<Double>)
${extraErrorCase ? `${extraErrorCase}\n` : ""}}

${disableTypeBodyLength ? "// swiftlint:disable:next type_body_length\n" : ""}struct ${name}: Codable, Equatable, Sendable {
${ranges}

    static let \`default\`: ${name} = {
        do {
            return try ${name}(
${defaults}
            )
        } catch {
            preconditionFailure("The contract-defined ${name} must be valid: \\(error)")
        }
    }()

${properties}

${disableInitializerLength ? "    // swiftlint:disable:next function_body_length\n" : ""}    init(
${parameters}
    ) throws {
${validations}${extraValidation ? `\n${extraValidation}` : ""}

${assignments}
    }

${disableDecodingLength ? "    // swiftlint:disable:next function_body_length\n" : ""}    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
${decoding}
        )
    }

    private static func validate(
        _ value: Double,
        field: String,
        range: ClosedRange<Double>
    ) throws {
        guard value.isFinite, range.contains(value) else {
            throw ${validationErrorName}.outOfRange(field: field, range: range)
        }
    }${extraMembers ? `\n\n${extraMembers}` : ""}
}`;
}

function renderComponentTypeScript({ protocol, style, listStyle }) {
  const enumTypes = Object.entries(style.enums)
    .map(([name, values]) => {
      const typeName = typeScriptEnumName(name);
      const valuesName = constantName(name, "VALUES");
      return `export const ${valuesName} = ${JSON.stringify(values)} as const;\nexport type ${typeName} = (typeof ${valuesName})[number];`;
    })
    .join("\n\n");
  const chart = renderTypeScriptStyle({ style, fields: style.fields, typeName: "ChartStyle", prefix: "CHART_STYLE" });
  const list = renderTypeScriptStyle({ style, fields: listStyle.fields, typeName: "BreakdownListStyle", prefix: "BREAKDOWN_LIST_STYLE", includeLayoutCheck: true });
  const commandNames = protocol.messages.webIncoming.filter((name) => name !== "ready" && name !== "styleChanged");

  return `// Generated by Scripts/generate-chart-inspector-contract.mjs.
// Source: Contracts/ChartInspectorContract.json. Do not edit directly.

export const INSPECTOR_PROTOCOL_VERSION = ${protocol.version};
export const MIN_INSPECTOR_REVISION = ${protocol.revisions.nativeMinimum};
export const FIRST_STYLE_CHANGE_REVISION = ${protocol.revisions.styleChangeMinimum};
export const MAX_INSPECTOR_REVISION = ${protocol.revisions.maximum};
export const INSPECTOR_SOURCE = ${JSON.stringify(protocol.sources.web)};
export const NATIVE_SOURCE = ${JSON.stringify(protocol.sources.native)};
export const NATIVE_STATE_MESSAGE = ${JSON.stringify(protocol.messages.nativeState)};

export const EDITABLE_COMPONENTS = ["chart", "list"] as const;
export type EditableComponent = (typeof EDITABLE_COMPONENTS)[number];

${enumTypes}

${chart}

${list}

export interface ChartNativeStateMessage {
  protocolVersion: number;
  type: typeof NATIVE_STATE_MESSAGE;
  source: string;
  revision: number;
  component: "chart";
  values: ChartStyle;
}

export interface ListNativeStateMessage {
  protocolVersion: number;
  type: typeof NATIVE_STATE_MESSAGE;
  source: string;
  revision: number;
  component: "list";
  values: BreakdownListStyle;
}

export type NativeStateMessage = ChartNativeStateMessage | ListNativeStateMessage;

export interface WebReadyMessage {
  protocolVersion: number;
  type: "ready";
  source: string;
}

export interface ChartWebStyleChangedMessage {
  protocolVersion: number;
  type: "styleChanged";
  source: string;
  revision: number;
  component: "chart";
  values: ChartStyle;
}

export interface ListWebStyleChangedMessage {
  protocolVersion: number;
  type: "styleChanged";
  source: string;
  revision: number;
  component: "list";
  values: BreakdownListStyle;
}

export type WebStyleChangedMessage = ChartWebStyleChangedMessage | ListWebStyleChangedMessage;

export interface WebCommandMessage {
  protocolVersion: number;
  type: ${commandNames.map((name) => JSON.stringify(name)).join(" | ")};
  source: string;
  component: EditableComponent;
}

export type WebMessage = WebReadyMessage | WebStyleChangedMessage | WebCommandMessage;

export function isNativeStateMessage(value: unknown): value is NativeStateMessage {
  if (!isRecord(value) || !isValidStateEnvelope(value)) {
    return false;
  }
  return (value.component === "chart" && isChartStyle(value.values)) ||
    (value.component === "list" && isBreakdownListStyle(value.values));
}

function isValidStateEnvelope(value: Record<string, unknown>): boolean {
  return value.protocolVersion === INSPECTOR_PROTOCOL_VERSION &&
    value.type === NATIVE_STATE_MESSAGE &&
    value.source === NATIVE_SOURCE &&
    Number.isInteger(value.revision) &&
    typeof value.revision === "number" &&
    value.revision >= MIN_INSPECTOR_REVISION &&
    value.revision <= MAX_INSPECTOR_REVISION;
}

function isChartColor(value: unknown): value is string {
  return value === ${JSON.stringify(style.color.accent)} ||
    (typeof value === "string" && /${style.color.hexPattern}/.test(value));
}

function isNumberInRange(value: unknown, minimum: number, maximum: number): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= minimum && value <= maximum;
}

function isOneOf<T extends string>(value: unknown, values: readonly T[]): value is T {
  return typeof value === "string" && values.includes(value as T);
}

function listLayoutFits(
  visibleRowCount: number,
  headerToRowsSpacing: number,
  rowHeight: number,
  rowSpacing: number,
): boolean {
  return 16 + headerToRowsSpacing + visibleRowCount * rowHeight +
    Math.max(visibleRowCount - 1, 0) * rowSpacing <= 144;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
`;
}

function renderTypeScriptStyle({ style, fields, typeName, prefix, includeLayoutCheck = false }) {
  const fieldDeclarations = fields.map((field) => `  ${field.name}: ${typeScriptType(field)};`).join("\n");
  const defaults = fields.map((field) => `  ${field.name}: ${JSON.stringify(field.default)},`).join("\n");
  const ranges = fields
    .filter((field) => field.type === "number" || field.type === "integer")
    .map((field) => `  ${field.name}: { minimum: ${field.minimum}, maximum: ${field.maximum}, step: ${field.step}, integer: ${field.type === "integer"} },`)
    .join("\n");
  const validations = fields.map((field) => `    ${typeScriptValidation(field)}`).join(" &&\n");
  const layoutCheck = includeLayoutCheck
    ? ` &&\n    listLayoutFits(value.visibleRowCount, value.headerToRowsSpacing, value.rowHeight, value.rowSpacing)`
    : "";

  return `export interface ${typeName} {
${fieldDeclarations}
}

export const ${prefix}_DEFAULT: ${typeName} = {
${defaults}
};

export const ${prefix}_RANGES = {
${ranges}
} as const;

export function is${typeName}(value: unknown): value is ${typeName} {
  if (!isRecord(value)) {
    return false;
  }
  return (
${validations}${layoutCheck}
  );
}`;
}

function renderComponentInspectorAdapter({ style, listStyle }) {
  const chart = renderInspectorAdapterComponent({
    style,
    fields: style.fields,
    prefix: "chart",
    typeName: "ChartStyle",
    constantPrefix: "CHART_STYLE",
  });
  const list = renderInspectorAdapterComponent({
    style,
    fields: listStyle.fields,
    prefix: "list",
    typeName: "BreakdownListStyle",
    constantPrefix: "BREAKDOWN_LIST_STYLE",
  });
  const enumValues = new Set([...style.fields, ...listStyle.fields]
    .filter((field) => field.type === "enum")
    .map((field) => constantName(field.enum, "VALUES")));
  const enumTypes = new Set([...style.fields, ...listStyle.fields]
    .filter((field) => field.type === "enum")
    .map((field) => typeScriptEnumName(field.enum)));

  return `// Generated by Scripts/generate-chart-inspector-contract.mjs.
// Source: Contracts/ChartInspectorContract.json. Do not edit directly.

import type { ResolvedValues } from "dialkit";
import {
  CHART_STYLE_DEFAULT,
  CHART_STYLE_RANGES,
  BREAKDOWN_LIST_STYLE_DEFAULT,
  BREAKDOWN_LIST_STYLE_RANGES,
${[...enumValues].map((name) => `  ${name},`).join("\n")}
} from "./contract";
import type { ChartStyle, BreakdownListStyle, ${[...enumTypes].join(", ")} } from "./contract";

${chart}

${list}

function dialRange(
  defaultValue: number,
  range: { minimum: number; maximum: number; step: number },
): [number, number, number, number] {
  return [defaultValue, range.minimum, range.maximum, range.step];
}
`;
}

function renderInspectorAdapterComponent({ style, fields, prefix, typeName, constantPrefix }) {
  const groups = new Map();
  for (const field of fields) {
    const groupFields = groups.get(field.inspector.group) ?? [];
    groupFields.push(field);
    groups.set(field.inspector.group, groupFields);
  }
  const pascalPrefix = pascalCase(prefix);
  const metadata = fields
    .map((field) => `  { name: ${JSON.stringify(field.name)}, path: ${JSON.stringify(`${field.inspector.group}.${field.inspector.key}`)}, control: ${JSON.stringify(field.inspector.control)} },`)
    .join("\n");
  const configGroups = [...groups]
    .map(([group, groupFields]) => `  ${group}: {\n${groupFields.map((field) => `    ${field.inspector.key}: ${typeScriptInspectorControlFor(field, constantPrefix)},`).join("\n")}\n  },`)
    .join("\n");
  const styleToDialGroups = [...groups]
    .map(([group, groupFields]) => `    ${group}: {\n${groupFields.map((field) => `      ${field.inspector.key}: ${typeScriptInspectorStyleValue(field, style)},`).join("\n")}\n    },`)
    .join("\n");
  const dialToStyleFields = fields
    .map((field) => `    ${field.name}: ${typeScriptInspectorDialValue(field)},`)
    .join("\n");

  return `export const ${prefix.toUpperCase()}_STYLE_INSPECTOR_FIELDS = [
${metadata}
] as const;

export const ${prefix}FieldConfig = {
${configGroups}
};

export function ${prefix}DialValuesFromStyle(style: ${typeName}) {
  return {
${styleToDialGroups}
  };
}

export function ${prefix}StyleFromDialValues(values: ResolvedValues<typeof ${prefix}FieldConfig>): ${typeName} {
  return {
${dialToStyleFields}
  };
}`;
}

function typeScriptInspectorControlFor(field, constantPrefix) {
  if (field.type === "boolean") return `${constantPrefix}_DEFAULT.${field.name}`;
  if (field.type === "color") return `{ type: "color" as const, default: ${constantPrefix}_DEFAULT.${field.name} }`;
  if (field.type === "enum") {
    return `{ type: "select" as const, options: [...${constantName(field.enum, "VALUES")}], default: ${constantPrefix}_DEFAULT.${field.name} }`;
  }
  return `dialRange(${constantPrefix}_DEFAULT.${field.name}, ${constantPrefix}_RANGES.${field.name})`;
}

function typeScriptInspectorControl(field) {
  if (field.type === "boolean") return `CHART_STYLE_DEFAULT.${field.name}`;
  if (field.type === "color") {
    return `{ type: "color" as const, default: CHART_STYLE_DEFAULT.${field.name} }`;
  }
  if (field.type === "enum") {
    return `{ type: "select" as const, options: [...${constantName(field.enum, "VALUES")}], default: CHART_STYLE_DEFAULT.${field.name} }`;
  }
  return `dialRange(CHART_STYLE_DEFAULT.${field.name}, CHART_STYLE_RANGES.${field.name})`;
}

function typeScriptInspectorStyleValue(field, style) {
  if (field.type !== "color") return `style.${field.name}`;
  return `style.${field.name} === ${JSON.stringify(style.color.accent)} ? ${JSON.stringify(field.inspector.accentDisplay)} : style.${field.name}`;
}

function typeScriptInspectorDialValue(field) {
  const value = `values.${field.inspector.group}.${field.inspector.key}`;
  return field.type === "enum" ? `${value} as ${typeScriptEnumName(field.enum)}` : value;
}

function swiftType(field) {
  if (field.type === "boolean") return "Bool";
  if (field.type === "color") return "ChartColor";
  if (field.type === "enum") return swiftEnumName(field.enum);
  if (field.type === "integer") return "Int";
  return "Double";
}

function swiftDefault(field, style) {
  if (field.type === "boolean") return String(field.default);
  if (field.type === "color") {
    if (field.default === style.color.accent) return ".accent";
    const [red, green, blue] = field.default
      .slice(1)
      .match(/.{2}/g)
      .map((component) => Number.parseInt(component, 16));
    return `.rgb(red: ${red}, green: ${green}, blue: ${blue})`;
  }
  if (field.type === "enum") return `.${field.default}`;
  return String(field.default);
}

function swiftDouble(value) {
  return Number.isInteger(value) ? `${value}.0` : String(value);
}

function swiftInteger(value) {
  return new Intl.NumberFormat("en-US").format(value).replaceAll(",", "_");
}

function swiftString(value) {
  return JSON.stringify(value);
}

function swiftEnumName(name) {
  return `Chart${pascalCase(name)}`;
}

function typeScriptType(field) {
  if (field.type === "boolean") return "boolean";
  if (field.type === "color") return "string";
  if (field.type === "enum") return typeScriptEnumName(field.enum);
  return "number";
}

function typeScriptEnumName(name) {
  return `Chart${pascalCase(name)}`;
}

function typeScriptValidation(field) {
  if (field.type === "boolean") return `typeof value.${field.name} === "boolean"`;
  if (field.type === "color") return `isChartColor(value.${field.name})`;
  if (field.type === "enum") {
    return `isOneOf(value.${field.name}, ${constantName(field.enum, "VALUES")})`;
  }
  const range = `isNumberInRange(value.${field.name}, ${field.minimum}, ${field.maximum})`;
  return field.type === "integer" ? `Number.isInteger(value.${field.name}) &&\n    ${range}` : range;
}

function constantName(name, suffix) {
  return `${name.replace(/([a-z])([A-Z])/g, "$1_$2").toUpperCase()}_${suffix}`;
}

function pascalCase(value) {
  return value.charAt(0).toUpperCase() + value.slice(1);
}

function relativePath(path) {
  return path.slice(repositoryRoot.length + 1);
}
