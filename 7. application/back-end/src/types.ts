// import { rawRequest } from '@dnorio/models-toolhq';
export interface DatabaseConfigParams {
  connectionName: 'postgres';
  port?: number;
  isActive?: boolean;
  options?: string[];
}

export interface GenerateMigrationParams {
  entityName: string;
}
