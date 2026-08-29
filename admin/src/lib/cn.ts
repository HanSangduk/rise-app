import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

// shadcn 관례의 className 병합 유틸(wodshot web과 동일 패턴).
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
