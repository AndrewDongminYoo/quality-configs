/**
 * The consumer environment must provide `dart` on PATH.
 * @see https://www.npmjs.com/package/prettier-plugin-markdown-dart
 * @type {import("prettier").Config}
 */
const config = {
  embeddedLanguageFormatting: "auto",
  endOfLine: "lf",
  plugins: ["prettier-plugin-markdown-dart"],
  printWidth: 100,
  proseWrap: "preserve",
  semi: true,
  tabWidth: 2,
  trailingComma: "es5",
  useTabs: false,
};

export default config;
