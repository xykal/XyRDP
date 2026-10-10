"use client";
import {signIn} from "next-auth/react";
export default function Button(){return <button onClick={()=>signIn("github",{callbackUrl:"/dashboard"})}>Masuk dengan GitHub →</button>}
