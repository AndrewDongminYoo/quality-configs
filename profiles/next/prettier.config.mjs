/**
 * Add tailwindStylesheet with a path relative to this file when using Tailwind CSS v4.
 * @see https://github.com/tailwindlabs/prettier-plugin-tailwindcss#specifying-your-tailwind-stylesheet-path-tailwind-css-v4
 * @type {import("prettier").Config & import("prettier-plugin-tailwindcss").PluginOptions}
 */
const config = {
  endOfLine: "lf",
  plugins: ["prettier-plugin-tailwindcss"],
  printWidth: 100,
  proseWrap: "preserve",
  semi: true,
  tabWidth: 2,
  trailingComma: "es5",
  useTabs: false,
};

export default config;
