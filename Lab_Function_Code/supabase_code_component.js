import React from "react";
import { createClient } from "@supabase/supabase-js";

// Initialize Supabase
const supabaseUrl = "https://vnuojnmhibfzsuwyqksp.supabase.co";
const supabaseKey = "xxx";
const supabase = createClient(supabaseUrl, supabaseKey);

export function AuthComponent() {
  const [user, setUser] = React.useState(null);
  const [email, setEmail] = React.useState("");
  const [password, setPassword] = React.useState("");

  // Check if the user is already logged in
  React.useEffect(() => {
    const checkSession = async () => {
      const { data: { session }, error } = await supabase.auth.getSession();
      if (session) {
        setUser(session.user);
      } else {
        setUser(null);
      }
    };

    checkSession();

    const { data: authListener } = supabase.auth.onAuthStateChange((event, session) => {
      if (session) {
        setUser(session.user);
      } else {
        setUser(null);
      }
    });

    return () => authListener.unsubscribe();
  }, []);

  // Handle login
  const handleLogin = async () => {
    const { data, error } = await supabase.auth.signInWithPassword({
      email: email,
      password: password,
    });
    if (error) console.error("Error:", error.message);
    else console.log("Logged in:", data.user);
  };

  // Handle logout
  const handleLogout = async () => {
    const { error } = await supabase.auth.signOut();
    if (error) console.error("Error:", error.message);
    else console.log("Logged out");
  };

  return (
    <div style={styles.container}>
      {user ? (
        <div>
          <p>Welcome, {user.email}</p>
          <button style={styles.button} onClick={handleLogout}>
            Logout
          </button>
        </div>
      ) : (
        <div>
          <input
            type="email"
            placeholder="Email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            style={styles.input}
          />
          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            style={styles.input}
          />
          <button style={styles.button} onClick={handleLogin}>
            Login
          </button>
        </div>
      )}
    </div>
  );
}

// Basic styles
const styles = {
  container: {
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "center",
    padding: "20px",
  },
  input: {
    padding: "10px",
    margin: "5px 0",
    width: "100%",
    borderRadius: "5px",
    border: "1px solid #ccc",
  },
  button: {
    padding: "10px 20px",
    backgroundColor: "#007BFF",
    color: "white",
    border: "none",
    borderRadius: "5px",
    cursor: "pointer",
  },
};