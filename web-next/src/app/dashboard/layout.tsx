import {getServerSession} from "next-auth";
import {authOptions} from "@/lib/auth";
import {redirect} from "next/navigation";
import Link from "next/link";
import Logout from "./logout";
export default async function Layout({children}:{children:React.ReactNode}){const session=await getServerSession(authOptions);if(!session)redirect("/login");return <><header><Link href="/dashboard"><b>RdpFree</b></Link><nav>{[["Home",""],["Folder","/folder"],["Settings","/settings"],["Logs","/logs"]].map(([label,path])=><Link key={label} href={"/dashboard"+path}>{label}</Link>)}</nav><span>{session.user?.name}</span><Logout/></header><main>{children}</main><footer>Credit: KallAncrit</footer></>}
