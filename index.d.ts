/**
 * Get the absolute path to the bundled CR-SQLite extension
 * @returns Absolute path to crsqlite.dylib/.so
 */
export declare function getExtensionPath(): string;

/**
 * Hip alias for getExtensionPath() - for use with db.loadExtension()
 * @returns Absolute path to crsqlite.dylib/.so
 */
export declare const pathToCRSQLiteExtension: string;

/**
 * Default export - same as getExtensionPath
 */
declare const _default: () => string;
export default _default;