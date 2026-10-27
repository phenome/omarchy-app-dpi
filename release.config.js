export default {
  branches: ["main"],
  plugins: [
    ["@semantic-release/commit-analyzer", { preset: "conventionalcommits" }],
    ["@semantic-release/release-notes-generator", { preset: "conventionalcommits" }],
    ["@semantic-release/changelog", { changelogFile: "CHANGELOG.md" }],
    "./scripts/release-version.js",
    [
      "@semantic-release/git",
      {
        assets: ["package.json", "manifest.json", "CHANGELOG.md"],
      },
    ],
    [
      "@semantic-release/github",
      {
        assets: ["preview.png", "screenshots/*.png"],
        successCommentCondition: false,
        failCommentCondition: false,
        labels: false,
        releasedLabels: false,
      },
    ],
  ],
};
