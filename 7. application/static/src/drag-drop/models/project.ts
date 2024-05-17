// Project State Management
export enum ProjectStatus {
  Active,
  InProgress,
  Finished
}

export type ProjectStringStatus = 'active' | 'in-progress' | 'finished';

export const convertProjectStatus = (projectStatus: ProjectStringStatus) => {
  if (projectStatus === 'active') {
    return ProjectStatus.Active;
  } else if (projectStatus === 'in-progress') {
    return ProjectStatus.InProgress;
  }
  return ProjectStatus.Finished;
}

export class Project {
  constructor(
    public id: string,
    public title: string,
    public description: string,
    public people: number,
    public status: ProjectStatus
  ) {}
}